package com.trippals.shared.database

import com.trippals.shared.domain.CacheAccessScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class CacheScopeTest {
    @Test
    fun `member cache scope cannot collide with public or another activity`() {
        val publicScope = CacheAccessScope.Public.storageKey
        val firstActivity = CacheAccessScope.ActivityMember("member-1", "activity-1").storageKey
        val secondActivity = CacheAccessScope.ActivityMember("member-1", "activity-2").storageKey

        assertNotEquals(publicScope, firstActivity)
        assertNotEquals(firstActivity, secondActivity)
        assertEquals("member:member-1:activity-1", firstActivity)
    }
}
