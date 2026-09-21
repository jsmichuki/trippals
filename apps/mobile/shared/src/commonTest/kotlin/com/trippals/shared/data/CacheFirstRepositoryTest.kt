package com.trippals.shared.data

import com.trippals.shared.domain.CacheAccessScope
import com.trippals.shared.domain.CacheFreshness
import com.trippals.shared.domain.CacheMetadata
import com.trippals.shared.domain.LoadPhase
import com.trippals.shared.domain.RepositoryError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals

class CacheFirstRepositoryTest {
    @Test
    fun `keeps stale cache visible after retryable refresh failure`() = runBlocking {
        val cache = MutableStateFlow(
            CacheSnapshot(
                value = listOf("cached"),
                metadata = CacheMetadata(
                    fetchedAtEpochMillis = 10,
                    expiresAtEpochMillis = 11,
                    scope = CacheAccessScope.Public,
                ),
            ),
        )
        val repository = CacheFirstRepository(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            cache = cache,
            nowEpochMillis = { 12 },
            isEmpty = { it.isEmpty() },
            refreshFromNetwork = {
                RefreshResult.Failure(RepositoryError("offline", "You appear to be offline.", retryable = true))
            },
            persist = { error("must not persist a failed refresh") },
        )

        repository.refresh()

        assertEquals(listOf("cached"), repository.state.value.data)
        assertEquals(CacheFreshness.Stale, repository.state.value.freshness)
        assertEquals(LoadPhase.Content, repository.state.value.phase)
        assertEquals("offline", repository.state.value.error?.code)
    }
}
