package com.trippals.shared.domain

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CacheModelsTest {
    @Test
    fun `expiry makes cache stale without using the device timezone`() {
        val metadata = CacheMetadata(
            fetchedAtEpochMillis = 1_000,
            expiresAtEpochMillis = 2_000,
            scope = CacheAccessScope.Account("member-1"),
        )

        assertFalse(metadata.isStale(1_999))
        assertTrue(metadata.isStale(2_000))
    }
}
