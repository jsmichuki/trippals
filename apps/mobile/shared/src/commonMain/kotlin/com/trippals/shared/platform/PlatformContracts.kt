package com.trippals.shared.platform

import kotlinx.coroutines.flow.StateFlow

/**
 * Platform services are injected into shared feature composition. They are
 * deliberately small: common code never imports platform UX or security APIs.
 */
interface PasskeyAuthenticator {
    suspend fun createCredential(creationOptionsJson: String): String
    suspend fun getAssertion(requestOptionsJson: String): String
}

/** A local screen lock, not a server authentication or authorization decision. */
interface LocalAppLock {
    suspend fun unlock(localizedReason: String): AppLockResult
}

enum class AppLockResult { UNLOCKED, CANCELLED, UNAVAILABLE }

interface NetworkReachabilityMonitor {
    val reachability: StateFlow<NetworkReachability>
    fun start()
    fun stop()
}

enum class NetworkReachability { AVAILABLE, UNAVAILABLE }

/** No implementation may invent a token when the OS push provider is unavailable. */
interface PushTokenProvider {
    suspend fun currentToken(): PushToken
}

sealed interface PushToken {
    data class Available(val value: String) : PushToken
    data object Unavailable : PushToken
}

/**
 * A deliberately payload-free seam for platform logging and crash reporting.
 * Callers must use correlation IDs and error codes; credentials, chat text,
 * private locations, evidence, and raw request/response bodies are forbidden.
 */
interface SafeTelemetry {
    fun event(name: String, correlationId: String? = null)
    fun recordFailure(code: String, correlationId: String? = null)
}
