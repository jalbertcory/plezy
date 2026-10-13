# Plezy Android download changes

Source: https://github.com/edde746/background_downloader

Exact revision: `09690d61b29fe81feb5495cc9a5dc4349c0caef3`. The original MIT `LICENSE` and source attribution are retained.

Local changes in this worktree:

- Android `TaskRunner.kt`: retain an opaque persisted task and use the callback-resolved URL only for the live request. Reject legacy app video tasks pending migration. Sanitize credential-task errors, response bodies, and response headers.
- Android `Callbacks.kt`: enable generated plugin registration in the headless callback engine so the app-owned Keystore channel is available. A disposable-emulator probe reproduced failure before this change and downloaded a local fake payload successfully afterward.
- Android `DownloadTaskRunner.kt`: avoid persisting resolved request information in failure responses.
- `lib/src/base_downloader.dart`: guard legacy video-task resume/status/progress persistence on Android. Other platform paths keep source behavior.

The Apple and desktop implementation files match the source revision. Broader modifications in the sibling worktree are not incorporated. These changes are prepared on `codex/android-credential-recovery` for separate draft PR review. The app's focused and affected host tests pass; Android debug compilation and 16 downloader JVM unit tests pass. The actual Android worker/headless callback path also passed on a disposable API 36 emulator with a fabricated URL and a 65,536-byte local response. Physical-device behavior remains unverified. See the root `FORK_CHANGES.md` for scope, migration, and validation status.
