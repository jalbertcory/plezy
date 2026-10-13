// Run only with --dart-define=PLEZY_DISPOSABLE_NATIVE_PROBE=true on the named
// disposable AVD. This is an alternate debug entrypoint, never the app startup.
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/services/android_credentials/android_credential_bindings.dart';
import 'package:plezy/services/android_credentials/android_credential_store.dart';
import 'package:plezy/services/android_credentials/android_download_credentials.dart';

void check(bool result, String label) {
  if (!result) throw StateError(label);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || !Platform.isAndroid || !const bool.fromEnvironment('PLEZY_DISPOSABLE_NATIVE_PROBE')) {
    throw StateError('Explicit disposable Android debug probe required');
  }
  check(!(await DeviceInfoPlugin().androidInfo).isPhysicalDevice, 'Emulator required');
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Plezy disposable credential probe'))),
    ),
  );
  final directory = await getApplicationDocumentsDirectory();
  final report = File('${directory.path}/plezy-native-probe-report.json');
  final stage = File('${directory.path}/plezy-native-probe-stage');
  final results = <String>[];
  AppDatabase? db;
  HttpServer? server;
  try {
    db = AppDatabase.forTesting(NativeDatabase(File('${directory.path}/plezy-native-probe.sqlite')));
    final registry = ConnectionRegistry(db);
    JellyfinConnection account(String id, String token) => JellyfinConnection(
      id: id,
      baseUrl: 'https://example.invalid',
      serverName: 'Disposable fake account',
      serverMachineId: 'fake-server',
      userId: id,
      userName: 'Fake user',
      accessToken: token,
      deviceId: 'fake-device',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final first = connectionCredentialOwner('native-probe-a', 'accessToken', 'Fake A', {'fake-server'});
    if (await stage.exists()) {
      check((await registry.get('native-probe-a') as JellyfinConnection).accessToken == 'fake-reauth', 'Restart read');
      check(
        (await registry.get('native-probe-b') as JellyfinConnection).accessToken == 'fake-other',
        'Other restart read',
      );
      results.add('Dart registry + native Keystore persisted through app force-stop/relaunch');
      await registry.clear();
      check((await db.select(db.connections).get()).isEmpty, 'Logout connection cleanup');
      check((await AndroidCredentialChannel().read(first.id)).state == 'missing', 'Logout native cleanup');
      await stage.delete();
      results.add('Registry logout cleanup deleted both fabricated accounts and their native items');
    } else {
      final legacy = account('native-probe-a', 'fake-legacy');
      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion(
              id: const Value('native-probe-a'),
              kind: const Value('jellyfin'),
              displayName: const Value('Fake A'),
              configJson: Value(jsonEncode(legacy.toConfigJson())),
              createdAt: const Value(1000),
            ),
          );
      await registry.upsert(account('native-probe-b', 'fake-other'));
      await AndroidCredentialBindings.checkAndMigrate(db);
      final row = await (db.select(db.connections)..where((t) => t.id.equals('native-probe-a'))).getSingle();
      check(
        (jsonDecode(row.configJson) as Map)['accessToken'].startsWith(AndroidCredentialStore.prefix),
        'Migration reference',
      );
      check(
        (await registry.get('native-probe-a') as JellyfinConnection).accessToken == 'fake-legacy',
        'Migration read',
      );
      results.add('Persisted SQLite legacy token migrated to real Keystore with verified readback');
      await AndroidCredentialStore.remove(first); // Controlled loss of this fabricated item only.
      AndroidCredentialFailure? failure;
      try {
        await registry.get('native-probe-a');
      } on AndroidCredentialFailure catch (error) {
        failure = error;
      }
      check(failure?.canReset == true, 'Missing item classified permanent');
      check(
        !await AndroidCredentialStore.resetAfterConfirmation(
          failure!,
          confirmed: false,
          stopTransfers: (_) async => throw StateError('Cancel must not stop transfers'),
        ),
        'Cancelled reset',
      );
      check((await AndroidCredentialChannel().read(first.id)).state == 'missing', 'Cancel unchanged');
      await AndroidCredentialStore.resetAfterConfirmation(failure, confirmed: true, stopTransfers: (_) async {});
      check((await registry.get('native-probe-a') as JellyfinConnection).accessToken.isEmpty, 'Reset requires reauth');
      check(
        (await registry.get('native-probe-b') as JellyfinConnection).accessToken == 'fake-other',
        'Other account unchanged',
      );
      await registry.upsert(account('native-probe-a', 'fake-reauth'));
      results.add(
        'Missing-item recovery: cancel, explicit scoped reset, unrelated account preserved, reauthentication',
      );
      await stage.writeAsString('restart-pending', flush: true);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        check(request.uri.queryParameters['token'] == 'fake-download-only', 'Fake request token');
        requests++;
        request.response.contentLength = 65536;
        request.response.add(List<int>.filled(65536, 42));
        await request.response.close();
      });
      final task = await protectAndroidDownload(
        DownloadTask(
          taskId: 'plezy-native-probe-download',
          url: 'http://127.0.0.1:${server.port}/fake.bin?token=fake-download-only',
          filename: 'plezy-native-probe-download.bin',
          group: 'video_downloads',
          metaData: 'fake-server:probe',
          retries: 0,
          updates: Updates.statusAndProgress,
        ),
      );
      check(!jsonEncode(task.toJson()).contains('fake-download-only'), 'Persisted task redaction');
      final status = await FileDownloader().download(task as DownloadTask).timeout(const Duration(seconds: 60));
      check(status.status == TaskStatus.complete, 'Background task status ${status.status.name}');
      check(requests == 1, 'One authenticated fake request');
      final downloaded = File(await task.filePath());
      check(await downloaded.length() == 65536, 'Downloaded bytes');
      await downloaded.delete();
      await removeAndroidDownloadCredential(task);
      await FileDownloader().database.deleteRecordWithId(task.taskId);
      results.add(
        'Actual Android worker + headless callback resolved Keystore URL and downloaded 65536 local fake bytes',
      );
    }
    await report.writeAsString(jsonEncode({'passed': true, 'results': results}), flush: true);
  } catch (error) {
    await report.writeAsString(
      jsonEncode({'passed': false, 'results': results, 'error': error.toString()}),
      flush: true,
    );
  } finally {
    await server?.close(force: true);
    await db?.close();
  }
}
