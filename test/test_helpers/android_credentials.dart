import 'package:flutter/services.dart';
import 'package:plezy/services/android_credentials/android_credential_store.dart';

/// Fabricated values only. No platform channel or native credential operation.
class FakeAndroidCredentialBackend implements AndroidCredentialBackend {
  final items = <String, AndroidCredentialItem>{};
  final failures = <String, String>{};
  final calls = <String>[];
  bool interruptReset = false;
  bool loseWrite = false;
  int _revision = 0;

  AndroidCredentialItem item(String id) => items[id] ?? const AndroidCredentialItem('missing', 'absent');
  Never fail(String id, String code) => throw PlatformException(
    code: code,
    message: 'fake-sensitive-native-message',
    details: {'revision': item(id).revision},
  );

  @override
  Future<AndroidCredentialItem> read(String id) async {
    calls.add('read:$id');
    if (item(id).state == 'reset_pending') fail(id, 'reset_pending');
    final failure = failures[id];
    if (failure != null) fail(id, failure);
    return item(id);
  }

  @override
  Future<AndroidCredentialItem> write(String id, String value) async {
    await read(id);
    calls.add('write:$id');
    if (loseWrite) return const AndroidCredentialItem('missing', 'absent');
    return items[id] = AndroidCredentialItem('ready', '${++_revision}', value);
  }

  @override
  Future<AndroidCredentialItem> reset(String id, String revision) async {
    calls.add('reset:$id');
    if (item(id).revision != revision || (item(id).state == 'ready' && failures[id] != 'permanent')) fail(id, 'stale');
    items[id] = AndroidCredentialItem('reset_pending', revision);
    if (interruptReset) fail(id, 'unavailable');
    failures.remove(id);
    return items[id] = AndroidCredentialItem('reauth', '${++_revision}');
  }

  @override
  Future<List<String>> listOwnedIds() async => items.keys.toList();

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    items.remove(id);
    failures.remove(id);
  }
}
