# Kotlin Multiplatform mobile workspace

This workspace uses shared state/domain/data code with native Android and iOS
shells. Android owns its navigation and rendering; iOS owns its SwiftUI
navigation and rendering. This keeps platform UX, permissions, deep links, and
accessibility behavior native while sharing API clients, DTOs, repositories,
SQLDelight cache, command replay, and `StateFlow` state in `shared`.

```text
shared/       Kotlin Multiplatform domain/data/network/cache + native source sets
androidApp/   Android app shell and Android navigation
iosApp/       SwiftUI shell and iOS composition
```

`shared` builds the `TripPalsShared` static framework for `iosArm64`,
`iosSimulatorArm64`, and `iosX64`. Xcode consumes that framework through the
usual local framework/package integration; an Xcode project is intentionally
not checked in until the iOS shell has screen requirements.

## Dependency and platform boundaries

`commonMain` is platform-neutral and provides Coroutines/Flow, Ktor HTTP and
WebSockets, Kotlin Serialization, Kotlinx DateTime, and SQLDelight runtime.
The Android and iOS source sets select their Ktor engine and SQLDelight driver.
Kotlin wire DTOs use `snake_case` JSON names and only call the Phoenix API;
there is no client database connection.

Native adapters never place sensitive material in shared persistent storage:

- Android's `AndroidKeystoreSecureSessionStore` encrypts the persisted session
  with a non-exportable Android Keystore AES-GCM key. It stores ciphertext only.
- Android passkeys use Credential Manager. iOS passkeys are implemented at the
  SwiftUI composition boundary with AuthenticationServices. Both return only
  the system-produced WebAuthn payload for server verification.
- Android app lock uses BiometricPrompt with device-credential fallback. iOS
  uses LocalAuthentication. Neither retains biometric results.
- Network reachability is native and only controls retry/reconnect UX; it is
  never evidence of API authorization or a successful command.
- Push token adapters are native (FCM/APNs). No token is fabricated when the
  provider is unavailable; push payloads contain identifiers, never private
  content.

Pass a concrete native adapter into feature composition instead of importing
Android or Apple APIs from `commonMain`. Platform navigation stays local rather
than being hidden behind `expect`/`actual`.

The shared layer owns API DTOs, Ktor transport, SQLDelight cache, repositories,
and safe idempotent command replay. Native layers own passkeys, platform app
lock, secure token storage, and push integration. Do not containerize native
mobile builds for local development; use the native SDK toolchains and CI.
