# Kotlin Multiplatform mobile workspace

Create the Gradle/Kotlin Multiplatform workspace here after the team selects
the UI boundary (shared Compose UI or native SwiftUI/Android shells). Keep this
shape:

```text
shared/       core, network, database, domain, data, optional shared UI
androidApp/   Credential Manager, Keystore, FCM, Android navigation shell
iosApp/       AuthenticationServices, Keychain, APNs, SwiftUI shell
```

The shared layer owns API DTOs, Ktor transport, SQLDelight cache, repositories,
and safe idempotent command replay. Native layers own passkeys, platform app
lock, secure token storage, and push integration. Do not containerize native
mobile builds for local development; use the native SDK toolchains and CI.
