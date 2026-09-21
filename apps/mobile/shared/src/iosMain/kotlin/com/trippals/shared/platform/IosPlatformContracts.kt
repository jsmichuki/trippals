package com.trippals.shared.platform

import com.trippals.shared.auth.SecureSessionStore

/**
 * iOS implementations live at the SwiftUI composition boundary, where they
 * can use Keychain, AuthenticationServices, LocalAuthentication, Network and
 * APNs without leaking Apple APIs into common code.
 */
/** iOS/Swift composition implements these shared contracts with Apple APIs. */
interface IosSecureSessionStore : SecureSessionStore

interface IosPasskeyAuthenticator : PasskeyAuthenticator

interface IosAppLock : LocalAppLock

interface IosNetworkReachabilityMonitor : NetworkReachabilityMonitor

interface IosPushTokenProvider : PushTokenProvider
