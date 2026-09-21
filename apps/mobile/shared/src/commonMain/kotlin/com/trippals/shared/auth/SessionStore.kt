package com.trippals.shared.auth

/**
 * Implemented by Keychain (iOS) and Keystore-backed encrypted storage (Android).
 * No implementation may log or persist these values in SQLDelight.
 */
interface SecureSessionStore {
    suspend fun accessToken(): String?
    suspend fun refreshToken(): String?
    suspend fun replace(tokens: SessionTokens)
    suspend fun clear()
}

data class SessionTokens(
    val accessToken: String,
    val refreshToken: String,
)
