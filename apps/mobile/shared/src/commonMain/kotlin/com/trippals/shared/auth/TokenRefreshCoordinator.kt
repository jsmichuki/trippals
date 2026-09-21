package com.trippals.shared.auth

import com.trippals.shared.network.ApiProblem
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Performs the one authenticated-session refresh operation, never a parallel refresh storm. */
fun interface SessionRefresher {
    suspend fun refresh(refreshToken: String): RefreshResult
}

sealed interface RefreshResult {
    data class Success(val tokens: SessionTokens) : RefreshResult
    /** Includes refresh-token reuse, revocation, expiry, and malformed credentials. */
    data class Rejected(val problem: ApiProblem? = null) : RefreshResult
    data class RetryableFailure(val problem: ApiProblem? = null, val cause: Throwable? = null) : RefreshResult
}

sealed interface RefreshOutcome {
    /** Another concurrent request completed refresh while this request was waiting. */
    data object AlreadyRefreshed : RefreshOutcome
    data object Refreshed : RefreshOutcome
    data class Rejected(val problem: ApiProblem?) : RefreshOutcome
    data class RetryableFailure(val problem: ApiProblem?, val cause: Throwable?) : RefreshOutcome
}

/**
 * The failed access token is part of the single-flight key. Once one request
 * rotates it, other requests waiting on this mutex observe the replacement and
 * retry without rotating the one-time refresh token again.
 */
class TokenRefreshCoordinator(
    private val sessions: SecureSessionStore,
    private val refresher: SessionRefresher,
) {
    private val refreshMutex = Mutex()

    suspend fun refreshAfterUnauthorized(failedAccessToken: String?): RefreshOutcome = refreshMutex.withLock {
        if (sessions.accessToken() != failedAccessToken) return@withLock RefreshOutcome.AlreadyRefreshed

        val refreshToken = sessions.refreshToken()
            ?: return@withLock RefreshOutcome.Rejected(problem = null)

        when (val result = refresher.refresh(refreshToken)) {
            is RefreshResult.Success -> {
                sessions.replace(result.tokens)
                RefreshOutcome.Refreshed
            }

            is RefreshResult.Rejected -> {
                // A rejected rotating refresh token is terminal for this device session.
                sessions.clear()
                RefreshOutcome.Rejected(result.problem)
            }

            is RefreshResult.RetryableFailure ->
                RefreshOutcome.RetryableFailure(result.problem, result.cause)
        }
    }
}
