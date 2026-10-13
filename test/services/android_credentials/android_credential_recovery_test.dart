import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/android_credentials/android_credential_bindings.dart';
import 'package:plezy/services/android_credentials/android_credential_recovery.dart';
import 'package:plezy/services/android_credentials/android_credential_store.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/credential_vault.dart';

import '../../test_helpers/android_credentials.dart';
import '../../test_helpers/prefs.dart';

void main() {
  late FakeAndroidCredentialBackend backend;
  const first = AndroidCredentialOwner('account-a', 'Account A', serverIds: {'server-a'});
  const second = AndroidCredentialOwner('account-b', 'Account B', serverIds: {'server-b'});
  setUp(() {
    resetSharedPreferencesForTest();
    backend = FakeAndroidCredentialBackend();
    AndroidCredentialStore.configureForTesting(backend, enabled: true);
  });
  tearDown(() => AndroidCredentialStore.configureForTesting(null));

  Future<AndroidCredentialFailure> failureFor(AndroidCredentialOwner owner, String reference) async {
    try {
      await AndroidCredentialStore.revealReference(reference, owner: owner);
    } on AndroidCredentialFailure catch (failure) {
      return failure;
    }
    throw StateError('Expected a fabricated storage failure');
  }

  test('permanent and transient native errors have different recovery choices', () async {
    final reference = await AndroidCredentialStore.save(first, 'fake-a');
    for (final entry in {'unavailable': false, 'permanent': true, 'unexpected': false}.entries) {
      backend.failures[first.id] = entry.key;
      final failure = await failureFor(first, reference);
      expect(failure.canReset, entry.value);
      expect(failure.toString(), isNot(contains('fake-sensitive')));
      expect(backend.item(first.id).value, 'fake-a');
    }
  });

  test('only resettable sign-in failures take a running app to recovery', () {
    const download = AndroidCredentialOwner('["download","task-1"]', 'Background download');
    for (final problem in AndroidCredentialProblem.values) {
      final failure = AndroidCredentialFailure(first, problem, 'rev');
      expect(failure.requiresRecovery, failure.canReset);
      expect(AndroidCredentialFailure(download, problem, 'rev').requiresRecovery, isFalse);
    }
  });

  test('transient lock can recover without a reset or data loss', () async {
    final reference = await AndroidCredentialStore.save(first, 'fake-a');
    backend.failures[first.id] = 'unavailable';
    final failure = await failureFor(first, reference);
    expect(
      await AndroidCredentialStore.resetAfterConfirmation(
        failure,
        confirmed: true,
        stopTransfers: (_) async => fail('Transient failure must not stop transfers'),
      ),
      isFalse,
    );
    backend.failures.clear();
    expect(await AndroidCredentialStore.revealReference(reference, owner: first), 'fake-a');
    expect(backend.calls.where((call) => call.startsWith('reset:')), isEmpty);
  });

  test('cancelling reset performs no storage or transfer operation', () async {
    final reference = await AndroidCredentialStore.save(first, 'fake-a');
    backend.failures[first.id] = 'permanent';
    final failure = await failureFor(first, reference);
    backend.calls.clear();
    expect(
      await AndroidCredentialStore.resetAfterConfirmation(
        failure,
        confirmed: false,
        stopTransfers: (_) async => fail('Cancelled reset must not stop transfers'),
      ),
      isFalse,
    );
    expect(backend.calls, isEmpty);
    expect(backend.item(first.id).value, 'fake-a');
  });

  test('confirmed reset affects one credential and reauthentication replaces it', () async {
    final a = await AndroidCredentialStore.save(first, 'fake-a');
    final b = await AndroidCredentialStore.save(second, 'fake-b');
    backend.failures[first.id] = 'permanent';
    final failure = await failureFor(first, a);
    expect(
      await AndroidCredentialStore.resetAfterConfirmation(
        failure,
        confirmed: true,
        stopTransfers: (servers) async {
          expect(servers.id, first.id);
          expect(backend.item(first.id).value, 'fake-a');
        },
      ),
      isTrue,
    );
    expect(await AndroidCredentialStore.revealReference(a, owner: first), isNull);
    expect(await AndroidCredentialStore.revealReference(b, owner: second), 'fake-b');
    expect(AndroidCredentialStore.reauthenticationRequired, contains(first.id));
    await AndroidCredentialStore.save(first, 'fake-new-sign-in');
    expect(await AndroidCredentialStore.revealReference(a, owner: first), 'fake-new-sign-in');
    expect(AndroidCredentialStore.reauthenticationRequired, isNot(contains(first.id)));
  });

  test('confirmed cleanup may remove derived keys without deadlocking the store', () async {
    final reference = await AndroidCredentialStore.save(first, 'fake-account');
    await AndroidCredentialStore.save(second, 'fake-derived-request');
    backend.failures[first.id] = 'permanent';
    final failure = await failureFor(first, reference);
    expect(
      await AndroidCredentialStore.resetAfterConfirmation(
        failure,
        confirmed: true,
        stopTransfers: (_) => AndroidCredentialStore.remove(second),
      ).timeout(const Duration(seconds: 2)),
      isTrue,
    );
    expect(backend.item(first.id).state, 'reauth');
    expect(backend.item(second.id).state, 'missing');
  });

  test('a newer sign-in rejects stale confirmation before stopping transfers', () async {
    final reference = await AndroidCredentialStore.save(first, 'fake-old');
    backend.failures[first.id] = 'permanent';
    final failure = await failureFor(first, reference);
    backend.failures.clear();
    await AndroidCredentialStore.save(first, 'fake-new');
    await expectLater(
      AndroidCredentialStore.resetAfterConfirmation(
        failure,
        confirmed: true,
        stopTransfers: (_) async => fail('Stale reset must not stop transfers'),
      ),
      throwsA(isA<AndroidCredentialFailure>().having((e) => e.problem, 'problem', AndroidCredentialProblem.stale)),
    );
    expect(await AndroidCredentialStore.revealReference(reference, owner: first), 'fake-new');
  });

  test('failed transfer cancellation prevents key reset', () async {
    final reference = await AndroidCredentialStore.save(first, 'fake-a');
    backend.failures[first.id] = 'permanent';
    final failure = await failureFor(first, reference);
    await expectLater(
      AndroidCredentialStore.resetAfterConfirmation(
        failure,
        confirmed: true,
        stopTransfers: (_) async => throw StateError('fake cancel failure'),
      ),
      throwsA(isA<AndroidCredentialFailure>()),
    );
    expect(backend.item(first.id).value, 'fake-a');
    expect(backend.calls.where((call) => call.startsWith('reset:')), isEmpty);
  });

  test('an interrupted reset needs another confirmation and then completes', () async {
    final reference = await AndroidCredentialStore.save(first, 'fake-a');
    backend.failures[first.id] = 'permanent';
    final failure = await failureFor(first, reference);
    backend.interruptReset = true;
    await expectLater(
      AndroidCredentialStore.resetAfterConfirmation(failure, confirmed: true, stopTransfers: (_) async {}),
      throwsA(isA<AndroidCredentialFailure>()),
    );
    final pending = await failureFor(first, reference);
    expect(pending.problem, AndroidCredentialProblem.resetPending);
    backend.interruptReset = false;
    await AndroidCredentialStore.resetAfterConfirmation(pending, confirmed: false, stopTransfers: (_) async {});
    expect(backend.item(first.id).state, 'reset_pending');
    await AndroidCredentialStore.resetAfterConfirmation(pending, confirmed: true, stopTransfers: (_) async {});
    expect(backend.item(first.id).state, 'reauth');
  });

  test('an interrupted migration reuses the verified item and preserves settings', () async {
    const key = 'user_profile-a_simkl_session';
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(key, 'fake-session');
    await prefs.setString('theme', 'dark');
    await AndroidCredentialStore.migrate(preferenceCredentialOwner(key), 'fake-session', (v) async => v);
    // Process stopped before its preference field was replaced.
    expect(prefs.getString(key), 'fake-session');
    final writes = backend.calls.where((call) => call.startsWith('write:')).length;
    expect(await AndroidCredentialPreferences.load(key), 'fake-session');
    expect(backend.calls.where((call) => call.startsWith('write:')).length, writes);
    expect(prefs.getString(key), startsWith(AndroidCredentialStore.prefix));
    expect(prefs.getString('theme'), 'dark');
  });

  test('reset during incomplete migration keeps legacy source but prevents replay', () async {
    const key = 'user_profile-a_simkl_session';
    final owner = preferenceCredentialOwner(key);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(key, 'fake-legacy');
    final reference = await AndroidCredentialStore.save(owner, 'fake-legacy');
    backend.failures[owner.id] = 'permanent';
    final failure = await failureFor(owner, reference);
    await AndroidCredentialStore.resetAfterConfirmation(failure, confirmed: true, stopTransfers: (_) async {});
    expect(await AndroidCredentialPreferences.load(key), isNull);
    expect(prefs.getString(key), 'fake-legacy');
    await AndroidCredentialPreferences.save(key, 'fake-reauthenticated');
    expect(await AndroidCredentialPreferences.load(key), 'fake-reauthenticated');
  });

  test('failed verified write keeps the migration source', () async {
    const key = 'user_profile-a_simkl_session';
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(key, 'fake-legacy');
    backend.loseWrite = true;
    await expectLater(AndroidCredentialPreferences.load(key), throwsA(isA<AndroidCredentialFailure>()));
    expect(prefs.getString(key), 'fake-legacy');
  });

  test('retry budget stays bounded across rebuilt screens and isolates owners', () {
    final budget = AndroidCredentialRetryBudget();
    const failure = AndroidCredentialFailure(first, AndroidCredentialProblem.unavailable, '1');
    expect(budget.take(failure), isTrue);
    expect(budget.take(failure), isTrue);
    expect(budget.take(failure), isFalse);
    expect(budget.remaining(const AndroidCredentialFailure(second, AndroidCredentialProblem.unavailable, '2')), 2);
  });

  test('non-Android vault behavior remains upstream and never invokes native backend', () async {
    AndroidCredentialStore.configureForTesting(backend, enabled: false);
    final protected = await CredentialVault.protect('fake-desktop');
    expect(protected, startsWith('enc:v1:'));
    expect(await CredentialVault.reveal(protected), 'fake-desktop');
    expect(backend.calls, isEmpty);
  });
}
