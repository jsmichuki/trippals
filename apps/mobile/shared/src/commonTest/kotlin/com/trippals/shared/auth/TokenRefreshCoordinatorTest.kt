package com.trippals.shared.auth

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking

class TokenRefreshCoordinatorTest {
    @Test
    fun `a second stale request reuses the session created by the first refresh`() = runBlocking {
        val store = MemorySessionStore(SessionTokens("expired", "refresh-1"))
        var calls = 0
        val coordinator = TokenRefreshCoordinator(store) {
            calls += 1
            RefreshResult.Success(SessionTokens("new-access", "new-refresh"))
        }

        assertIs<RefreshOutcome.Refreshed>(coordinator.refreshAfterUnauthorized("expired"))
        assertIs<RefreshOutcome.AlreadyRefreshed>(coordinator.refreshAfterUnauthorized("expired"))
        assertEquals(1, calls)
        assertEquals("new-access", store.accessToken())
    }

    @Test
    fun `rejected refresh clears the device session`() = runBlocking {
        val store = MemorySessionStore(SessionTokens("expired", "revoked-refresh"))
        val coordinator = TokenRefreshCoordinator(store) { RefreshResult.Rejected() }

        assertIs<RefreshOutcome.Rejected>(coordinator.refreshAfterUnauthorized("expired"))
        assertNull(store.accessToken())
        assertNull(store.refreshToken())
    }

    private class MemorySessionStore(initial: SessionTokens?) : SecureSessionStore {
        private var tokens = initial

        override suspend fun accessToken(): String? = tokens?.accessToken

        override suspend fun refreshToken(): String? = tokens?.refreshToken

        override suspend fun replace(tokens: SessionTokens) {
            this.tokens = tokens
        }

        override suspend fun clear() {
            tokens = null
        }
    }
}
