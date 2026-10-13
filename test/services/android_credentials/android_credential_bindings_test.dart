import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/database/download_operations.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/services/android_credentials/android_credential_bindings.dart';
import 'package:plezy/services/android_credentials/android_credential_store.dart';

import '../../test_helpers/android_credentials.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/download_fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeAndroidCredentialBackend backend;
  late ConnectionRegistry connections;
  setUp(() {
    resetSharedPreferencesForTest();
    backend = FakeAndroidCredentialBackend();
    AndroidCredentialStore.configureForTesting(backend, enabled: true);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
  });
  tearDown(() async {
    await db.close();
    AndroidCredentialStore.configureForTesting(null);
  });

  JellyfinConnection account(String id, String token) => JellyfinConnection(
    id: id,
    baseUrl: 'https://example.test',
    serverName: 'Example $id',
    serverMachineId: 'server-$id',
    userId: 'user-$id',
    userName: 'Example',
    accessToken: token,
    deviceId: 'fake-device',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  test('reset and reauth retain both connection rows and downloaded media', () async {
    await connections.upsert(account('a', 'fake-a'));
    await connections.upsert(account('b', 'fake-b'));
    await db.insertDownload(
      serverId: ServerId('server-a'),
      ratingKey: 'movie',
      globalKey: 'server-a:movie',
      type: 'movie',
      status: DownloadStatus.completed.index,
    );
    final owner = connectionCredentialOwner('a', 'accessToken', 'Example a', {'server-a'});
    backend.failures[owner.id] = 'permanent';
    AndroidCredentialFailure? failure;
    try {
      await AndroidCredentialBindings.checkAndMigrate(db);
    } on AndroidCredentialFailure catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    await AndroidCredentialStore.resetAfterConfirmation(
      failure!,
      confirmed: true,
      stopTransfers: (ids) async {
        expect(ids.id, owner.id);
        expect(ids.serverIds, {'server-a'});
      },
    );
    await AndroidCredentialBindings.checkAndMigrate(db);
    expect((await connections.get('a') as JellyfinConnection).accessToken, '');
    expect((await connections.get('b') as JellyfinConnection).accessToken, 'fake-b');
    expect(await db.getDownloadedMedia('server-a:movie'), isNotNull);
    expect(await db.select(db.connections).get(), hasLength(2));
    await connections.upsert(account('a', 'fake-reauthenticated'));
    expect((await connections.get('a') as JellyfinConnection).accessToken, 'fake-reauthenticated');
    expect((await connections.get('b') as JellyfinConnection).accessToken, 'fake-b');
    final stored = await (db.select(db.connections)..where((t) => t.id.equals('a'))).getSingle();
    expect((jsonDecode(stored.configJson) as Map)['accessToken'], startsWith(AndroidCredentialStore.prefix));
    expect(stored.configJson, isNot(contains('fake-reauthenticated')));
  });

  test('interrupted connection migration retains legacy source through reset and metadata edits', () async {
    final original = account('a', 'fake-legacy');
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion(
            id: const Value('a'),
            kind: const Value('jellyfin'),
            displayName: const Value('Example a'),
            configJson: Value(jsonEncode(original.toConfigJson())),
            createdAt: const Value(1000),
          ),
        );
    await AndroidCredentialBindings.connection(
      'jellyfin',
      'a',
      'Example a',
      Map<String, dynamic>.from(original.toConfigJson()),
    ); // secure write, no DB commit
    final owner = connectionCredentialOwner('a', 'accessToken', 'Example a', {'server-a'});
    backend.failures[owner.id] = 'permanent';
    AndroidCredentialFailure? failure;
    try {
      await AndroidCredentialBindings.checkAndMigrate(db);
    } on AndroidCredentialFailure catch (error) {
      failure = error;
    }
    await AndroidCredentialStore.resetAfterConfirmation(failure!, confirmed: true, stopTransfers: (_) async {});
    final projection = await connections.get('a') as JellyfinConnection;
    expect(projection.accessToken, '');
    await connections.upsert(projection.copyWith(serverName: 'Renamed'));
    final row = await (db.select(db.connections)..where((t) => t.id.equals('a'))).getSingle();
    expect((jsonDecode(row.configJson) as Map)['accessToken'], 'fake-legacy');
    await connections.upsert(account('a', 'fake-reauthenticated'));
    expect((await connections.get('a') as JellyfinConnection).accessToken, 'fake-reauthenticated');
  });

  test('removing one account deletes only its native items', () async {
    await connections.upsert(account('a', 'fake-a'));
    await connections.upsert(account('b', 'fake-b'));
    await connections.remove('a');
    expect(await connections.get('a'), isNull);
    expect((await connections.get('b') as JellyfinConnection).accessToken, 'fake-b');
    expect(backend.items.length, 1);
  });
}
