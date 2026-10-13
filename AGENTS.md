# Work on the Plezy fork

## Default to Android

Implement new fork behavior for Android by default. Consider Android TV and Fire TV when a change touches their shared Android code or resources. Record those effects explicitly.

Ask Cory before propagating feature behavior to macOS, Windows, or iOS. Do not silently extend a change to Linux, tvOS, web, or another platform. An earlier broad draft is not approval to ship that behavior after the Android-first policy was adopted.

Shared Dart code can change every supported app. Before editing it, inspect callers, startup, persistence, and background workers across platforms. Isolate Android behavior behind a platform adapter or explicit platform selection, and preserve other platforms' existing behavior. A shared helper refactor is acceptable only when its behavior stays unchanged outside Android.

If separation would be unsafe, stop the affected implementation and explain the architectural decision. Ask whether to authorize specific additional platforms or defer that part. Do not disable other apps, change their stored-data formats, or add a plaintext fallback to avoid the decision.

## Keep the fork's change record current

Read `FORK_CHANGES.md` before feature work or an upstream sync. Update it in the same change whenever behavior, dependencies, migrations, platform scope, or validation status changes.

For each divergence, record:

- Intent and the affected files or directories.
- Approved platform scope and any platforms awaiting opt-in.
- Exact upstream baseline commit and source repository or ref.
- Migration, rollback, and compatibility concerns.
- Tests actually run, their results, and checks still pending.
- Whether the change is a local draft, committed, released, or abandoned.

Record real commit IDs after commits exist. Never report a planned test as passing. Keep entries concise and exclude secrets, account data, and device credentials.

Before an upstream sync, record the old baseline and inspect overlap with fork changes. After the sync, record the new baseline, retained or superseded changes, conflict resolutions, and validation. Preserve useful history instead of replacing it with an empty checklist.

## Preserve attribution and unfinished work

Keep Plezy's license and upstream attribution. For vendored dependencies, retain their license, source URL, exact revision, and a description of local modifications.

Preserve uncommitted work before changing scope. Use a separate checkout, branch, or verified patch when necessary. Do not cherry-pick or copy the pending multiplatform credential draft wholesale into Android-first work. Consult its entry in `FORK_CHANGES.md` first.

## Current task constraints

Cory approved installing Flutter/Dart and required Android build tools on 2026-10-03. Reuse suitable installations and prefer explicit local tool paths. CocoaPods and non-Android setup remain outside scope. Obtain explicit approval before accepting a new SDK license agreement or an unexpected permission/security change. Use fabricated credentials and mocked stores for host tests. Cory also authorized actual Keystore validation using only fabricated accounts in the fresh Plezy_Disposable_API36_Arm64 emulator; never use the existing personal AVD or a personal device. Do not inspect real credential values or use personal credential stores. Native validation is limited to fabricated values in the authorized disposable emulator.

No push, pull request, release, or platform expansion is authorized by this file. Follow the user's current instructions for those actions.
