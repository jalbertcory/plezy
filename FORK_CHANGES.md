# Plezy fork changes

This record tracks differences from [edde746/plezy](https://github.com/edde746/plezy). The personal fork is [jalbertcory/plezy](https://github.com/jalbertcory/plezy).

## Baseline and branch scope

The verified local baseline is `96504b618d99113434029080e52d5e3413ec588d`. Local `origin/main` and `upstream/main` both resolve to that commit. Their default branch is `main`. This verification does not assert that the remote upstream has not advanced since the last fetch.

| Branch | Purpose | Feature status |
| --- | --- | --- |
| `android-first` | Active Android-first work, created from the baseline | Local, uncommitted Android credential recovery implementation; host tests and Android debug build pass; device validation pending |
| `secure-credential-storage` | Preserved earlier shared and native credential draft | Uncommitted, unreleased, unvalidated draft; broader platforms pending explicit opt-in |

The original October 3 checkout layout used sibling directories: `plezy-android-first` and `plezy`. Those checkouts used the same Git repository and remotes. The original checkout retains all earlier feature edits. The original credential draft remains preserved without a feature commit on `android-first`. The separate review branch is recorded below. No merge or release has occurred.

## Android-first policy — local documentation change

Intent: default fork updates to Android and require a decision before propagating behavior to other apps.

Files: root `AGENTS.md`, `FORK_CHANGES.md`, and the fork-policy note in `README.md`. Copies also accompany the preserved draft. This changes agent instructions and documentation, not app runtime behavior or platform builds.

Baseline: `edde746/plezy` at `96504b618d99113434029080e52d5e3413ec588d`.

Status: policy committed locally on `android-first` as `2f2b24da288ba068350469578a50f172f3cd9846` (subsequent change-record edits are uncommitted). The preserved draft carries uncommitted copies of these documents. This policy commit accompanies the separate Android credential PR requested by Cory on October 13. The original checkout retains the Android-only runtime draft described below.

Validation: worktree branch and baseline inspected; both documents reviewed; `git diff --check` used for whitespace validation. These checks covered the policy commit only; runtime validation remains pending.

## Credential storage — preserved draft, not ready to ship

Intent: remove saved account tokens, refresh tokens, cookies, passwords, and authenticated download URLs from ordinary preference or task records. Keep nonsecret settings and downloaded media.

Baseline: `edde746/plezy` at `96504b618d99113434029080e52d5e3413ec588d`. The draft has no feature commit ID.

Approved direction: Android first. The draft predates this restriction and changes shared behavior. Its macOS, Windows, iOS, Linux, and tvOS paths are pending opt-in. The active branch uses a separate Android-only implementation and selectively adapts the Android downloader patch; the broader draft remains preserved.

Affected areas in the preserved checkout:

| Area | Files or directories | Draft scope |
| --- | --- | --- |
| Credential backend and migration | `lib/services/secure_credential_store.dart`, `credential_vault.dart`, `credential_preferences.dart`, `credential_migration.dart`, `lib/main.dart` | Shared startup and reference format; Android Keystore-backed plugin plus pending non-Android backends |
| Account and profile ownership | `lib/connection/`, `lib/profiles/`, `lib/database/app_database.dart`, `lib/screens/profile/profile_teardown.dart` | Shared scoped credentials, serialized migration, deletion, and logout |
| Saved sessions and preferences | `lib/services/storage_service.dart`, `sensitive_prefs.dart`, `prefs_recovery.dart`, `server_registry.dart`, tracker and Seerr stores, `lib/models/seerr/seerr_session.dart` | Shared migration of session JSON and legacy fields |
| Background downloads | `lib/services/secure_download_request.dart`, `download_manager_service.dart`, `lib/providers/download_provider.dart`, `packages/background_downloader/` | Android request-only URL resolution; shared task lifecycle; pending Apple and desktop modifications |
| Platform integration | `android/app/src/main/AndroidManifest.xml`, `tvos/Runner/AppDelegate.swift`, `.github/workflows/`, `linux/packaging/`, `pubspec.yaml` | Android backup disabled; Apple bridge, Linux packaging, and broad dependency integration remain pending |
| Tests and documentation | `test/flutter_test_config.dart`, credential/download tests, adapted registry/storage/profile tests, `test/test_helpers/`, `CREDENTIAL_STORAGE.md`, `README.md` | Fake backends and implementation notes; not a platform validation claim |

The draft pins `flutter_secure_storage` to 11.2.0. Its vendored downloader comes from [edde746/background_downloader](https://github.com/edde746/background_downloader) at `09690d61b29fe81feb5495cc9a5dc4349c0caef3`, retaining the MIT license and local patch notes. Plezy's original license and attribution remain intact.

Migration and compatibility concerns:

- Scoped `secure:v2:` references replace old preference or database values only after secure writes are read back. The legacy AES key is copied to secure storage before its preference copy is removed.
- Preference and identity operations are serialized in the process. OS storage and SQLite/preferences do not share a transaction. Interrupted operations can require reauthentication.
- A locked or unavailable store fails closed. Automatic Android reset is disabled. Missing secure items and corrupted storage are different cases; corrupted-key recovery remains incomplete, as described below.
- Live legacy download tasks are retired before secure requeueing. Completed files remain; interrupted legacy transfers restart. Paused rows remain paused. Logout cancels native transfers before credential deletion.
- The iOS draft protects resume archives in Keychain, but Apple's background URLSession owns the real authenticated request internally. That platform design is pending opt-in.
- Historical backups, SQLite free pages/WAL, and old recovery images are not securely erased. This work did not inspect or purge user data.
- Shared schema and startup changes cannot safely be made Android-only by deleting native Apple files. Android-first work needs a platform adapter that preserves the upstream credential format and behavior elsewhere. If that boundary cannot be maintained, ask before expanding scope.
- Old app builds may not understand newly stored references. Do not assume downgrades are compatible or activate migration before the recovery and rollback behavior is reviewed.

Validation of the preserved draft:

- Passed: 13 Linux dependency-check Python tests, Android manifest XML parsing, changed Python module parsing, and Git whitespace checks.
- Passed: Swift syntax parsing for the tvOS bridge and changed downloader files; isolated macOS type checking of the resume-store helper with a stub task type. These do not prove a Flutter/iOS/tvOS build works and do not approve platform expansion.
- Written, not run: 12 vault/migration tests and eight download credential/logout tests, including two new Android invalidation cases. Existing adapted tests and vendored plugin tests are also unrun.
- Pending: dependency resolution and generated lock/registrant updates, Dart formatting, analyzer, all Dart tests, Android build/device tests, and any separately approved platform builds.
- Flutter, Dart, and CocoaPods are absent from PATH. SDK approval remains pending. No real credential backend was invoked.

## Android corrupted-key review — gap in the preserved draft

Read-only source: [PR #762 author's comment](https://github.com/edde746/plezy/pull/762#issuecomment-4136044755), on a closed, unmerged upstream proposal. The author described brittle recovery when old keys become corrupted. No code or patch from that proposal was imported.

Preserved draft behavior: `AndroidOptions(resetOnError: false)` prevents automatic destructive reset. `SecureCredentialStore` converts native failures into a payload-free error. Reference and legacy source values remain available after failed reads, writes, or deletes.

Mock additions in the preserved draft: `test/test_helpers/secure_credentials.dart` can simulate permanent invalidation. `test/services/credential_vault_test.dart` checks repeated failure after migration without clearing references, and failure during migration without erasing the legacy source. These are regression specifications, not executed evidence of native Keystore behavior.

Gap in the preserved draft: the draft maps permanent key invalidation and temporary lock failures to the same retry path. A permanently unusable namespace can block startup, and logout can also fail while trying to delete its items. Retrying cannot restore lost cryptographic keys. The draft has no explicit user-directed credential reset and reauthentication flow. Do not turn on global automatic reset or delete application databases to hide this failure.

Before Android rollout, design a deliberate recovery path that preserves media and nonsecret settings, stops authenticated background tasks, limits deletion to app-owned credential state, and requests reauthentication. Distinguish temporary unavailability from permanent loss where the native API supports it. Validate locked, permanently invalidated, missing, restored, and interrupted-migration cases using fake credentials, followed by an approved Android test environment.

## Android credential recovery — local implementation draft

Intent: distinguish temporary storage failure from permanent key loss and provide an explicit, scoped reset followed by reauthentication. Status: committed for draft PR review on `codex/android-credential-recovery` at `19b6ebdf7faae90f1b6c13958e99bcd42a2918fb`. Host and fabricated-account disposable-emulator results are recorded below; additional device coverage remains pending. The original `android-first` copy remains uncommitted. No merge or release. Baseline remains `96504b618d99113434029080e52d5e3413ec588d`.

Scope: Android, including shared Android TV and Fire TV code. Root `AGENTS.md` applies in this worktree. The original `secure-credential-storage` checkout is preserved. Shared Dart entry points select the new adapter only on Android; other platforms retain upstream persistence and startup paths. The new native plugin declares Android only. The downloader's Apple and desktop sources are identical to its pinned source revision.

Implementation:

- `packages/android_credential_store/`: per-item Android Keystore AES-GCM keys, verified writes, payload-free error classification, revision checks, and a journal for interrupted reset. A confirmed reset removes one alias and ciphertext. There is no automatic reset or namespace-wide recovery deletion.
- `lib/services/android_credentials/`, `lib/widgets/android_credential_recovery_view.dart`, and `lib/main.dart`: startup/runtime failure routing, two manual checks per credential per app session, 15-second native-call bounds, a separate confirmation with Cancel focused by default, and an explicit continuation to sign-in. Temporary or unknown errors offer no reset. Interrupted reset requires renewed confirmation.
- Connection/profile registries, tracker/Seerr stores, `storage_service.dart`, and `app_database.dart`: Android-only migration and serialized identity changes. References replace source fields only after native readback; failed migration keeps legacy sources. Reset markers prevent automatic replay of retained legacy values. Fresh authentication replaces the selected credential.
- `download_manager_service.dart`, download provider/teardown, and the vendored downloader: Android task records use opaque references. Only a live HTTP request receives the resolved URL. Confirmed recovery stops tasks attributable to the selected sign-in. Full logout separately stops all app download tasks and removes app-owned credentials. Completed media and account/profile rows are not recovery cleanup targets.
- Android backup XML excludes the new ciphertext file but retains nonsecret reset/reauthentication journals, avoiding automatic replay after a restore.

Compatibility and remaining limits:

- Native storage and SQLite/preferences are separate commits. Revision checks, readback, and journals limit partial-operation effects; device testing is still required.
- Existing unscoped downloads and Plex local-profile downloads can lack sufficient account provenance. Recovery refuses reset before any cancellation when affected task ownership is ambiguous. This conservative block needs a product decision or an explicit task-provenance migration before broad rollout; it does not authorize cancelling another account's tasks.
- Reauthentication uses the existing account sign-in screen. Tracker/Seerr recovery directs users to the relevant profile's Settings. Native UI and TV focus behavior are unverified.
- Legacy AES keys and bootstrap values remain for recovery. Historical backup copies and SQLite free pages/WAL are not purged. This draft does not claim complete historical secret erasure.
- Older builds cannot interpret `android-secure:v1:` references. Do not downgrade a migrated data directory without a recovery plan.
- Android Keystore availability and the downloader's headless Flutter plugin registration require device validation, including missing keys, transient locks, corrupted ciphertext, restored data, and interruption between each persistence step.

Validation actually completed: Git whitespace check; XML parsing of the manifest, both backup rules, and plugin manifest; source comparison against downloader revision `09690d61b29fe81feb5495cc9a5dc4349c0caef3` confirmed exactly two Android Kotlin changes and one Android-guarded Dart change (plus local patch documentation).

Now **passing**: 25 focused fake-store/widget tests under `test/services/android_credentials/` and `test/widgets/android_credential_recovery_view_test.dart`. Cases cover permanent/transient failures, cancelled and successful scoped reset, stale confirmation, cancellation failure, interrupted reset/migration, preserved legacy values, reauthentication, unrelated accounts/media, download references, ownership ambiguity, bounded checks, and the non-Android vault path.

Dependency resolution, lockfile regeneration, Dart formatting/analyzer, and focused/affected tests are complete. Android debug compilation succeeded; fake-account emulator/device tests and Android TV/Fire TV focus checks remain pending. SDK installation was subsequently approved and completed; see the toolchain validation entry below. No real credential operation was performed.

See [Android recovery developer notes](ANDROID_CREDENTIAL_RECOVERY.md) and [downloader provenance](packages/background_downloader/PLEZY_PATCHES.md).

## Toolchain installation and host validation — 2026-10-03

Cory explicitly approved Flutter/Dart and required Android build tools. Root `AGENTS.md` now records that approval while retaining the restriction on new license acceptance and non-Android setup.

Tools:

- Installed official Flutter **3.47.1**, matching CI, at `../toolchains/flutter-3.47.1`; verified tag commit `6655482ec06e547f90abf8ae7590466f4415978d`. Bundled Dart is **3.13.1**. Source: https://github.com/flutter/flutter/releases/tag/3.47.1. Commands use explicit paths; shell profiles and global Git settings were not changed.
- Reused Android Studio's **OpenJDK 21.0.9**, Android command-line tools **20.0**, Platform Tools **37.0.1**, platform **36 revision 2**, and Build Tools **36.1.0** in the existing user SDK.
- Installed project-pinned **NDK 29.0.14206865** and **CMake 4.1.2** through the installed SDK manager. Gradle also required and installed **NDK 28.2.13676358** and **CMake 3.22.1** for plugin builds. Existing SDK licenses covered these packages; no new prompt was accepted, and no yes-to-all command was used.
- Gradle **9.6.1** uses the repository wrapper and pinned checksum. Pub/Gradle caches and Flutter configuration are task-local. Flutter bootstrap fetched its bundled host tooling, including iOS USB helper artifacts; no CocoaPods, Apple SDK installation, or Apple build was performed.

Results:

- `flutter pub get --no-example` succeeded. The root lockfile changes only the new local Android plugin and the pinned downloader's path source. Existing wakelock development dependencies were resolved with `--enforce-lockfile --no-example`, matching CI.
- Dart formatting completed for 25 changed/new Dart files. `flutter analyze --no-pub`: **No issues found**.
- Focused fake-store/widget suite: **25 passed**. Fixed a stale callback assertion and reset the injected store queue in each widget test's FakeAsync zone; neither change accesses native credentials.
- Existing Android downloader JVM unit tests: **16 passed**, no failures/errors/skips (`:background_downloader:testDebugUnitTest`). These do not exercise Android Keystore hardware or real background engines.
- Existing affected suites: **558 passed**, covering connections, profiles, vault/storage, downloads, trackers, Seerr, startup, database download operations, and profile teardown.
- First Android debug build reached the new plugin's Kotlin compile and exposed Java 17/Kotlin 21 target mismatch. Its Kotlin target now explicitly matches Java 17. Rebuild succeeded: `build/app/outputs/flutter-apk/app-debug.apk` (debug, Android arm64). Both the credential plugin and patched downloader compiled. The APK was not installed or launched. SHA-256: `b5d0b14c01ee7a24c218c2bff3b8510689d0b8a26dceafadc85b32c9241fe88e`.

Build warnings concern existing KGP migration and deprecated Gradle APIs; these did not fail the pinned build. Logs and a machine-readable summary are saved locally at `../validation/plezy-android-first/`.

All test credentials are fabricated. No app was launched against user data, no real credential operation ran, and no push/release occurred. Android Keystore hardware behavior, background Flutter-engine registration at runtime, backup/restore, and TV/Fire TV remote focus still require isolated device tests.

## Native target availability and delivery checkpoint — 2026-10-03

Read-only inventory found no connected Android target and one existing Play Store-enabled `Pixel_9_Pro_Fold` AVD. It is not an identified disposable target, so it was not started or modified. Actual Keystore, device migration/restart/logout, background-engine execution, backup/restore, and TV focus remain unverified. The smallest next prerequisite is a fresh disposable AVD using the already-installed Android 36 ARM64 image; no personal-device installation is authorized.

No explicit new SDK license agreement was accepted. The SDK manager used closed stdin, and Gradle reused pre-existing acceptance records. Both installed SDK license files retain modification timestamps from 2026-03-13 02:39:32 UTC, months before this task. No yes-to-all license command was used. The user's approval covered tool installation; it was not treated as acceptance of a new agreement.

A compact validation report and a complete binary-capable patch against the baseline are prepared under `../validation/plezy-android-first/`. `git apply --cached --check` against a temporary baseline index verifies patch applicability without changing the worktree index. The debug APK is 269,388,832 bytes; its SHA-256 appears in the toolchain entry above.

## Disposable Android native validation — 2026-10-03

Cory authorized a fresh disposable AVD. Created `Plezy_Disposable_API36_Arm64`, using the already-installed Android 36 ARM64 Play Store system image, with 2 GB RAM and two vCPUs. Data lives at `../avds/Plezy_Disposable_API36_Arm64.avd`; the existing `Pixel_9_Pro_Fold` AVD was not modified. No Google login, personal device, new software, or new license acceptance was used.

Added opt-in `AndroidCredentialDeviceTest.kt` instrumentation and a guarded alternate debug entrypoint, `integration_test/android_credential_probe.dart`. The probe does not replace normal app startup. It uses fabricated accounts, a separate SQLite file, and a loopback HTTP server. Native tests require an explicit disposable-test runner argument and an emulator check.

Verified:

- Four native instrumentation cases pass: actual Keystore write/read/delete across recreated Flutter engines; controlled deletion of one fabricated Keystore alias with permanent-loss classification and scoped reset; seeding a fabricated item; and reading/deleting it in a separate app process after force-stop. Unrelated items and a fabricated legacy recovery value remained intact. This tests missing-key loss, not biometric/lock-screen invalidation on physical hardware.
- The Dart probe passed persisted SQLite legacy migration with real Keystore readback, cancelled reset, confirmed missing-item reset, preservation of another fabricated account, and reauthentication. A second launch after force-stop read the same native values and cleared both fabricated accounts through the registry logout cleanup path.
- The probe reproduced a real background failure: the downloader used `FlutterEngine(context, null, false)`, disabling plugin registration. Android `Callbacks.kt` now uses the default registering constructor. The patched worker/headless callback completed a real 65,536-byte download from the probe's loopback server using a fabricated credential URL. The normal task object remained an opaque reference.
- Analysis remains clean; the 16 downloader JVM tests passed again after the callback-engine fix. The normal Android arm64 debug APK rebuilt successfully. Earlier 25 focused and 558 affected host tests remain the recorded passing runs.
- Instrumentation build uncovered three pre-existing MPV test calls using a callback as the new leading Boolean argument. Updated these Android-only test calls to `dispose(onComplete = ...)`; no player behavior changed.

Remaining limits: no backup/restore test, no Android TV/Fire TV image or focus test, no physical hardware/biometric invalidation, no transient locked-store device test, and no full interactive remote-server login/logout UI test. The actual native checks used fabricated values in an isolated emulator; they do not validate real accounts. Ambiguous legacy transfer ownership still deliberately blocks recovery.

The normal app reached its signed-out Plex/Jellyfin/Emby screen; UI hierarchy evidence is saved locally. The disposable emulator was then shut down and remains reusable.

The same Library report and patch identities are updated for these results. The APK is not attached or re-uploaded in this follow-up. No push/release occurred.

## Upstream sync history

No upstream sync has occurred after the baseline above. Future sync entries must record old and new commit IDs, affected fork entries, conflict resolutions, and tests actually run.

## Separate Android credential PR — 2026-10-13

Intent: publish the existing Android-only credential implementation for review independently of [player/language PR #1](https://github.com/jalbertcory/plezy/pull/1). The isolated branch retains the Android-first fork policy commit `2f2b24da288ba068350469578a50f172f3cd9846` and is based on fork `main` at upstream baseline `96504b618d99113434029080e52d5e3413ec588d` from `edde746/plezy`. No upstream sync occurred. The saved pre-player diff and archive reproduced the credential source exactly; no player/language feature files were copied.

Scope: Android, including Android TV and Fire TV shared credential, migration, recovery, and background-download paths. Other platforms retain their existing adapters and vendored downloader behavior. The older multiplatform credential draft is preserved and excluded. Dependencies add the local Android-only plugin and replace the already-pinned downloader with the same revision plus documented Android changes. Existing MIT and Plezy GPL attribution remain intact.

Compatibility: `android-secure:v1:` references require this implementation. Legacy source values are retained until verified native migration succeeds. Do not downgrade a migrated data directory without a recovery plan. Legacy (non-`android-secure`) download tasks are left untouched by recovery; reference tasks whose owner cannot be resolved are cancelled with the reset rather than blocking it (see the review fixes below); backup/restore, TV focus, and other device limits above remain rollout prerequisites. Status: implementation committed as `19b6ebdf7faae90f1b6c13958e99bcd42a2918fb` on `codex/android-credential-recovery` for draft PR review, unreleased. Cory authorized the separate PR on October 13; merge and release remain outside scope.

Validation in the isolated PR checkout: **571 focused/affected host tests** and **168 additional database/service/sign-in tests** passed with fabricated fixtures and mocked stores. The exact CI analyzer guard passed with zero diagnostics. Formatting of all 25 app/plugin/test Dart files, credential XML parsing, app/local-patch whitespace, icon consistency, generated-file verification, strict translation hygiene, CI script guards, and unused-code/file checks passed. The Android arm64 debug APK built successfully using the approved existing SDK/JDK/cache paths. All **16 downloader JVM tests** passed with no failures, errors, or skips. Existing KGP/Gradle warnings remain. Vendored comparison verified the pinned revision and unchanged MIT license: 142 source files match, with only the three documented Android Kotlin files and Android-guarded Dart file modified.

The October 3 disposable-emulator results above are retained historical evidence, not new runs. No emulator, personal device, or real credential store was accessed during PR preparation. Remote CI, backup/restore, TV/Fire TV focus, physical invalidation, transient locks, and full remote sign-in UI remain pending. Logs and the source-preservation snapshot are local under `/private/tmp/plezy-credential-pr-20261013/`. New recovery UI copy is English; translation remains pending.

Whitespace scope: the imported upstream downloader contains existing trailing whitespace. It is retained for source identity, including untouched Apple/desktop files. Application changes and the four local vendor patches pass whitespace checks against their respective baselines.

## Credential PR review fixes — 2026-10-13

Intent: address review findings on [PR #2](https://github.com/jalbertcory/plezy/pull/2) before merge. Commit: `25dd8d9222b83dc2064090afe8335009464f3060` on `review/pr2`, rebased onto fork `main` after the upstream sync.

- `packages/background_downloader/.../Callbacks.kt`: the headless callback engine no longer auto-registers every plugin. It registers only `AndroidCredentialStorePlugin`, by reflection. Auto-registration let `os_media_controls` replace the live media-session token from a background download callback. `packages/android_credential_store/android/consumer-rules.pro` keeps the plugin constructor under R8. `PLEZY_PATCHES.md` records the change.
- `android_credential_recovery.dart`: transfer stopping skips legacy tasks and cancels reference tasks with unresolved ownership, instead of throwing and blocking the reset.
- `android_credential_store.dart` and `lib/main.dart`: only resettable sign-in failures send a running app to the recovery screen. A download-scoped failure stays with its download.
- `download_manager_service.dart`: the per-task credential is removed best-effort after a complete, canceled or not-found status, even when status handling throws.
- Declined: reclassifying `UnrecoverableKeyException` as transient. A truly lost key would then never offer a reset.
- Not addressed (minor): delete journaling, credential cleanup for failed tasks, backup restore forcing a reset, and a Plex server without `clientIdentifier` keeping its `enc:v1` token.

Validation in the session worktree: the CI quality steps passed (format, generated files, translations, icons, analyzer, unused code/files). The full `flutter test` run passed, **7,969 tests** with 6 skipped. The Android arm64 debug APK built. No emulator, device, or real credential store was used. Device validation remains pending.
