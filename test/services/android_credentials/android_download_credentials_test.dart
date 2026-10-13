import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/android_credentials/android_credential_store.dart';
import 'package:plezy/services/android_credentials/android_download_credentials.dart';

import '../../test_helpers/android_credentials.dart';

void main() {
  late FakeAndroidCredentialBackend backend;
  setUp(() {
    backend = FakeAndroidCredentialBackend();
    AndroidCredentialStore.configureForTesting(backend, enabled: true);
  });
  tearDown(() => AndroidCredentialStore.configureForTesting(null));
  const url = 'https://example.test/video?token=fake-download-secret';

  test('persistent task has only a reference while the request resolves the URL', () async {
    final task = await protectAndroidDownload(DownloadTask(taskId: 'a', url: url, metaData: 'server-a:movie'));
    final stored = jsonEncode(task.toJson());
    expect(stored, isNot(contains('fake-download-secret')));
    expect((await resolveAndroidDownload(task))!.url, url);
    expect(jsonEncode(task.toJson()), stored);
  });

  test('missing or locked download key fails without sending the placeholder URL', () async {
    final task = await protectAndroidDownload(DownloadTask(taskId: 'a', url: url));
    backend.failures[androidDownloadOwner(task).id] = 'unavailable';
    await expectLater(
      resolveAndroidDownload(task),
      throwsA(isA<PlatformException>().having((e) => e.toString(), 'safe error', isNot(contains('fake-sensitive')))),
    );
    backend.failures.clear();
    await removeAndroidDownloadCredential(task);
    await expectLater(resolveAndroidDownload(task), throwsA(isA<PlatformException>()));
  });

  test('another task cannot borrow the same reference and unrelated keys survive deletion', () async {
    final a = await protectAndroidDownload(DownloadTask(taskId: 'a', url: url));
    final b = await protectAndroidDownload(DownloadTask(taskId: 'b', url: url));
    await expectLater(resolveAndroidDownload(a.copyWith(taskId: 'b')), throwsA(isA<PlatformException>()));
    await removeAndroidDownloadCredential(a);
    expect((await resolveAndroidDownload(b))!.url, url);
  });
}
