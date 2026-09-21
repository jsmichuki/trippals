package com.trippals.shared.data

import com.trippals.shared.domain.BrowsePreference
import com.trippals.shared.domain.CacheAccessScope
import com.trippals.shared.domain.CachedActivityIdea
import com.trippals.shared.domain.CachedActivityPreview
import com.trippals.shared.domain.CachedInvitationSummary
import com.trippals.shared.domain.CachedMessage
import com.trippals.shared.domain.CachedNotification
import com.trippals.shared.domain.CachedPlanSummary
import kotlinx.coroutines.flow.Flow

/**
 * SQLDelight-backed implementation belongs behind this interface. The public
 * cache is separate from account-scoped content so logout/access revocation can
 * remove private data without wiping a guest's browsing preference.
 */
interface CacheStore : PendingCommandStore {
    fun observeBrowsePreference(): Flow<BrowsePreference?>
    suspend fun saveBrowsePreference(preference: BrowsePreference)

    fun observeActivityPreviews(cityId: String): Flow<CacheSnapshot<List<CachedActivityPreview>>>
    suspend fun replaceActivityPreviews(cityId: String, rows: List<CachedActivityPreview>)
    fun observeActivityIdeas(cityId: String): Flow<CacheSnapshot<List<CachedActivityIdea>>>
    suspend fun replaceActivityIdeas(cityId: String, rows: List<CachedActivityIdea>)

    fun observePlans(scope: CacheAccessScope.Account): Flow<CacheSnapshot<List<CachedPlanSummary>>>
    suspend fun replacePlans(scope: CacheAccessScope.Account, rows: List<CachedPlanSummary>)
    fun observeInvitations(scope: CacheAccessScope.Account): Flow<CacheSnapshot<List<CachedInvitationSummary>>>
    suspend fun replaceInvitations(scope: CacheAccessScope.Account, rows: List<CachedInvitationSummary>)
    fun observeMessages(scope: CacheAccessScope.ActivityMember): Flow<CacheSnapshot<List<CachedMessage>>>
    suspend fun replaceMessages(scope: CacheAccessScope.ActivityMember, rows: List<CachedMessage>)
    fun observeNotifications(scope: CacheAccessScope.Account): Flow<CacheSnapshot<List<CachedNotification>>>
    suspend fun replaceNotifications(scope: CacheAccessScope.Account, rows: List<CachedNotification>)

    /** Removes private cached content for an account or a more specific scope. */
    suspend fun deleteScoped(scope: CacheAccessScope)
}
