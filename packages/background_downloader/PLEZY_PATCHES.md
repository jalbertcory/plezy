# Plezy Android download changes

Source: https://github.com/edde746/background_downloader

Exact revision: `ebdf69a7bdd03d410bfdfc700add08eed0de161d` (rebased from `09690d61b29fe81feb5495cc9a5dc4349c0caef3`). The original MIT `LICENSE` and source attribution are retained.

Local changes in this worktree:

- Android `TaskRunner.kt`: retain an opaque persisted task and use the callback-resolved URL only for the live request. Reject legacy app video tasks pending migration. Sanitize credential-task errors, response bodies, and response headers.
- Android `Callbacks.kt`: keep generated plugin registration disabled in the headless callback engine and register only the app-owned Keystore plugin (`com.plezy.credentials.AndroidCredentialStorePlugin`, looked up by name and kept by that plugin's consumer R8 rules). Auto-registering every plugin there re-attached the app's media session and downloader channels to the headless engine.
- Android `DownloadTaskRunner.kt`: avoid persisting resolved request information in failure responses.
- `lib/src/base_downloader.dart`: guard legacy video-task resume/status/progress persistence on Android. Other platform paths keep source behavior.

The Apple and desktop implementation files match the source revision. Broader modifications in the sibling worktree are not incorporated. These changes are committed in `19b6ebdf7faae90f1b6c13958e99bcd42a2918fb` on `codex/android-credential-recovery` for separate draft PR review. The app's focused and affected host tests pass; Android debug compilation and 16 downloader JVM unit tests pass. The actual Android worker/headless callback path also passed on a disposable API 36 emulator with a fabricated URL and a 65,536-byte local response. Physical-device behavior remains unverified. See the root `FORK_CHANGES.md` for scope, migration, and validation status.
