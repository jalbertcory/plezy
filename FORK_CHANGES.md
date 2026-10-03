# Plezy fork changes

This record tracks differences from [edde746/plezy](https://github.com/edde746/plezy). The personal fork is [jalbertcory/plezy](https://github.com/jalbertcory/plezy).

## Baseline and branch scope

The verified local baseline is `96504b618d99113434029080e52d5e3413ec588d`. Local `origin/main` and `upstream/main` both resolve to that commit. Their default branch is `main`. This verification does not assert that the remote upstream has not advanced since the last fetch.

| Branch | Purpose | Feature status |
| --- | --- | --- |
| `android-first` | Active Android-first work, created from the baseline | Policy and change-record documents only; credential implementation has not been applied |
| `secure-credential-storage` | Preserved earlier shared and native credential draft | Uncommitted, unreleased, unvalidated draft; broader platforms pending explicit opt-in |

The checkouts are sibling directories: `plezy-android-first` and `plezy`. Both use the same Git repository and remotes. The original checkout retains all earlier feature edits. No feature commit, push, pull request, or release has been created for the credential draft.

## Android-first policy — local documentation change

Intent: default fork updates to Android and require a decision before propagating behavior to other apps.

Files: root `AGENTS.md`, `FORK_CHANGES.md`, and the fork-policy note in `README.md`. Copies also accompany the preserved draft. This changes agent instructions and documentation, not app runtime behavior or platform builds.

Baseline: `edde746/plezy` at `96504b618d99113434029080e52d5e3413ec588d`.

Status: committed locally on `android-first`; consult `git log -- AGENTS.md FORK_CHANGES.md README.md` for the actual commit ID. The preserved draft carries uncommitted copies of these documents. No publication is authorized. The active checkout has no credential schema or native storage changes.

Validation: worktree branch and baseline inspected; both documents reviewed; `git diff --check` used for whitespace validation. App tests are not needed for this documentation-only branch.

## Credential storage — preserved draft, not ready to ship

Intent: remove saved account tokens, refresh tokens, cookies, passwords, and authenticated download URLs from ordinary preference or task records. Keep nonsecret settings and downloaded media.

Baseline: `edde746/plezy` at `96504b618d99113434029080e52d5e3413ec588d`. The draft has no feature commit ID.

Approved direction: Android first. The draft predates this restriction and changes shared behavior. Its macOS, Windows, iOS, Linux, and tvOS paths are pending opt-in. None of that runtime implementation is on `android-first`.

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

## Android corrupted-key review — recovery gap

Read-only source: [PR #762 author's comment](https://github.com/edde746/plezy/pull/762#issuecomment-4136044755), on a closed, unmerged upstream proposal. The author described brittle recovery when old keys become corrupted. No code or patch from that proposal was imported.

Current draft behavior: `AndroidOptions(resetOnError: false)` prevents automatic destructive reset. `SecureCredentialStore` converts native failures into a payload-free error. Reference and legacy source values remain available after failed reads, writes, or deletes.

Mock additions in the preserved draft: `test/test_helpers/secure_credentials.dart` can simulate permanent invalidation. `test/services/credential_vault_test.dart` checks repeated failure after migration without clearing references, and failure during migration without erasing the legacy source. These are regression specifications, not executed evidence of native Keystore behavior.

Remaining gap: the draft maps permanent key invalidation and temporary lock failures to the same retry path. A permanently unusable namespace can block startup, and logout can also fail while trying to delete its items. Retrying cannot restore lost cryptographic keys. The draft has no explicit user-directed credential reset and reauthentication flow. Do not turn on global automatic reset or delete application databases to hide this failure.

Before Android rollout, design a deliberate recovery path that preserves media and nonsecret settings, stops authenticated background tasks, limits deletion to app-owned credential state, and requests reauthentication. Distinguish temporary unavailability from permanent loss where the native API supports it. Validate locked, permanently invalidated, missing, restored, and interrupted-migration cases using fake credentials, followed by an approved Android test environment.

## Upstream sync history

No upstream sync has occurred after the baseline above. Future sync entries must record old and new commit IDs, affected fork entries, conflict resolutions, and tests actually run.
