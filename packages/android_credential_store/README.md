# Android credential store

Local Android-only Flutter plugin for Plezy. Each SHA-256 scope ID owns one Android Keystore AES-256-GCM alias. Ciphertext uses a random IV and binds the scope ID as authenticated data. No plaintext fallback is implemented.

The channel `com.plezy/android_credentials` exposes `read`, `write`, `reset`, `delete`, and `listOwnedIds`. The last operation reads only this plugin's preference keys, not the device's full Keystore. `delete` is for explicitly requested account removal/logout. Recovery uses `reset` with an expected revision and a separate UI confirmation.

Errors expose only `unavailable`, `permanent`, `reset_pending`, or `stale`, plus an opaque revision. Temporary authentication failures take precedence over permanent causes. Unknown failures remain unavailable. Reset journals precede alias deletion; unfinished reset is never resumed automatically. Reauthentication tombstones prevent retained legacy sources from silently migrating again.

The ciphertext file is excluded from backup by the app. Nonsecret reset journals remain eligible for backup. The plugin does not require biometric authentication; it must support approved background downloads. A disposable Android 36 emulator validated actual read/write/delete, process restart, and scoped reset after deliberate loss of a fabricated key. Physical hardware and biometric invalidation behavior remain unverified.

References: [Android Keystore](https://developer.android.com/privacy-and-security/keystore) and [permanent invalidation exception](https://developer.android.com/reference/android/security/keystore/KeyPermanentlyInvalidatedException).

This implementation is a draft for review under the root Plezy license. Host fake-store tests pass. The Android debug build and four disposable-emulator instrumentation cases pass. Only fabricated values were used in the test app sandbox.
