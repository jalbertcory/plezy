import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/android_credentials/android_credential_store.dart';
import 'package:plezy/widgets/android_credential_recovery_view.dart';

import '../test_helpers/android_credentials.dart';

void main() {
  late FakeAndroidCredentialBackend backend;
  const owner = AndroidCredentialOwner('fake-owner', 'Example account');
  setUp(() {
    backend = FakeAndroidCredentialBackend();
    AndroidCredentialStore.configureForTesting(backend, enabled: true);
  });
  tearDown(() => AndroidCredentialStore.configureForTesting(null));

  Future<AndroidCredentialFailure> brokenSignIn() async {
    // Create the queue inside this widget test's FakeAsync zone.
    AndroidCredentialStore.configureForTesting(backend, enabled: true);
    final reference = await AndroidCredentialStore.save(owner, 'fake-token');
    backend.failures[owner.id] = 'permanent';
    try {
      await AndroidCredentialStore.revealReference(reference, owner: owner);
    } on AndroidCredentialFailure catch (error) {
      return error;
    }
    throw StateError('Expected fake failure');
  }

  testWidgets('permanent reset has a separate confirmation and cancel leaves data intact', (tester) async {
    final failure = await brokenSignIn();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidCredentialRecoveryView(
            failure: failure,
            retriesRemaining: 2,
            onRetry: () {},
            onContinue: () {},
            stopTransfers: (_) async => fail('Cancel must not stop transfers'),
          ),
        ),
      ),
    );
    backend.calls.clear();
    await tester.tap(find.text('Reset this sign-in…'));
    await tester.pumpAndSettle();
    expect(find.text('Reset this saved sign-in?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.calls, isEmpty);
    expect(backend.item(owner.id).value, 'fake-token');
  });

  testWidgets('confirmed scoped reset exposes an explicit reauthentication continuation', (tester) async {
    final failure = await brokenSignIn();
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidCredentialRecoveryView(
            failure: failure,
            retriesRemaining: 2,
            onRetry: () {},
            onContinue: () => continued = true,
            stopTransfers: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reset this sign-in…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset this sign-in'));
    await tester.pumpAndSettle();
    expect(backend.item(owner.id).state, 'reauth');
    expect(continued, isFalse);
    await tester.tap(find.text('Continue to sign in'));
    expect(continued, isTrue);
  });

  testWidgets('unknown or temporary failure never offers reset and exhausted checks stop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidCredentialRecoveryView(
            failure: const AndroidCredentialFailure(owner, AndroidCredentialProblem.unavailable, 'unknown'),
            retriesRemaining: 0,
            onRetry: () => fail('Retry budget exhausted'),
            onContinue: () {},
            stopTransfers: (_) async => fail('Transient failure must not reset'),
          ),
        ),
      ),
    );
    expect(find.text('Reset this sign-in…'), findsNothing);
    expect(find.textContaining('Check again ('), findsNothing);
    expect(find.textContaining('No more checks this session.'), findsOneWidget);
  });
}
