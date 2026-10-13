# Android credential recovery draft

This review branch is `codex/android-credential-recovery`; its source draft remains preserved on `android-first`. The upstream baseline is Plezy `96504b618d99113434029080e52d5e3413ec588d`. It is not ready to release. The older multiplatform draft remains in the sibling `plezy` checkout.

## Recovery behavior

1. A failed read preserves the source value and reports a safe error. The UI names the affected account or service without exposing the credential.
2. Temporary or unknown failures allow at most two manual checks per credential per session. Each channel call has a 15-second bound. No automatic destructive retry runs.
3. Permanent loss offers a separate reset confirmation. Cancel is the default focused action, including on Android TV and Fire TV.
4. After confirmation, the app verifies that the failure revision is current, checks download ownership, stops affected transfers, and resets only that credential's alias and ciphertext. Healthy or replaced items reject stale confirmation.
5. A nonsecret reauthentication marker prevents legacy values from being reused automatically. Account/profile rows, media, unrelated keys, settings, and uncommitted legacy migration sources remain.
6. Continue opens the existing sign-in flow for account credentials. For tracker/Seerr sessions, select the affected profile and reconnect the service in Settings.

Reset does not delete a database or wipe the secure-storage namespace. Interrupted reset requires confirmation again. Explicit whole-app logout remains a separate operation.

## Platform and migration boundary

Android alone uses the new native plugin and `android-secure:v1:` references. Shared code selects the adapter using the actual platform; tests inject an explicit override. Other platforms retain the upstream AES/preferences paths. The vendored downloader changes three Android files and Android-guarded sections of one Dart file; its Apple and desktop sources match the pinned baseline.

Migration verifies native readback before replacing a source field. Native storage and application persistence cannot commit atomically; staged writes are reused after interruption. The legacy AES key and old bootstrap fields are retained for recovery. Historical copies are not securely erased. A migrated Android data directory is not safe to open with an old app build.

Download cleanup relies on nonsecret account provenance. If a legacy or Plex local-profile task cannot be assigned to one account, reset stops before cancelling any task or deleting the selected key. Do not replace this guard with server-wide cancellation. Adding durable per-task account provenance is a remaining rollout decision.

## Validation still required

SDK installation was approved. Flutter 3.47.1/Dart 3.13.1, dependency resolution, formatting, and analysis are complete. The focused command is:

```sh
flutter test test/services/android_credentials test/widgets/android_credential_recovery_view_test.dart
```

The 558 existing affected tests also pass. The Android arm64 debug APK also builds successfully. Test the headless downloader with fabricated accounts on an emulator/device. Exercise permanent loss, temporary lock, missing items after restore, interrupted migration/reset, stale confirmation, cancelled confirmation, multi-account scope, reauthentication, full logout, and TV remote focus.

All 25 focused cases, 558 affected existing tests, and 16 downloader JVM unit tests pass. Analysis reports no issues; XML and whitespace checks passed. The Android debug build passes; physical-device behavior remains unverified; disposable-emulator results are recorded below. No real credentials were read, written, reset, or configured. See `FORK_CHANGES.md` for detailed file scope and provenance.

## Disposable native validation

`Plezy_Disposable_API36_Arm64` is a reusable isolated Android 36 phone AVD (2 GB RAM, two CPUs). Four real Keystore instrumentation cases and the guarded `integration_test/android_credential_probe.dart` passed with fabricated values. The probe verified migration, reset cancellation, scoped reset/re-authentication, actual headless-worker download, process restart, and registry logout cleanup. It exposed and fixed disabled plugin registration in the Android downloader callback engine.

No backup/restore, TV-focus, hardware biometric invalidation, or full remote login UI result is claimed. Never run the probe against a personal device or the existing personal AVD. The `PLEZY_DISPOSABLE_NATIVE_PROBE=true` debug define is required; the regular app entrypoint is unchanged.

## Separate PR validation — 2026-10-13

The isolated credential review branch passed 571 focused/affected host tests, 168 additional database/service/sign-in tests, 16 downloader JVM tests, the repository’s analysis and quality guards, and an Android arm64 debug build. All host stores were mocked. The earlier disposable-emulator results were not rerun. Remaining device and rollback limits above still apply.
