package com.trippals.shared.data

import com.trippals.shared.domain.BrowsePreference
import com.trippals.shared.domain.CacheAccessScope
import com.trippals.shared.domain.CachedActivityIdea
import com.trippals.shared.domain.CachedActivityPreview
import com.trippals.shared.domain.CachedInvitationSummary
import com.trippals.shared.domain.CachedMessage
import com.trippals.shared.domain.CachedNotification
import com.trippals.shared.domain.CachedPlanSummary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow

/** Remote interfaces remain DTO-free so the future network mapper owns wire concerns. */
interface DiscoverRemoteDataSource {
    suspend fun loadActivityPreviews(cityId: String): RefreshResult<List<CachedActivityPreview>>
    suspend fun loadActivityIdeas(cityId: String): RefreshResult<List<CachedActivityIdea>>
}

interface MemberRemoteDataSource {
    suspend fun loadPlans(scope: CacheAccessScope.Account): RefreshResult<List<CachedPlanSummary>>
    suspend fun loadInvitations(scope: CacheAccessScope.Account): RefreshResult<List<CachedInvitationSummary>>
    suspend fun loadMessages(scope: CacheAccessScope.ActivityMember): RefreshResult<List<CachedMessage>>
    suspend fun loadNotifications(scope: CacheAccessScope.Account): RefreshResult<List<CachedNotification>>
}

/** Keeps guest browse preferences local and distinct from invitation availability. */
class BrowsePreferencesRepository(private val cache: CacheStore) {
    fun observe(): Flow<BrowsePreference?> = cache.observeBrowsePreference()
    suspend fun save(preference: BrowsePreference) = cache.saveBrowsePreference(preference)
}

class DiscoverRepository(
    private val cache: CacheStore,
    private val remote: DiscoverRemoteDataSource,
    private val scope: CoroutineScope,
    private val nowEpochMillis: () -> Long,
) {
    fun activityPreviews(cityId: String): CacheFirstRepository<List<CachedActivityPreview>> =
        CacheFirstRepository(
            scope = scope,
            cache = cache.observeActivityPreviews(cityId),
            nowEpochMillis = nowEpochMillis,
            isEmpty = { it.isEmpty() },
            refreshFromNetwork = { remote.loadActivityPreviews(cityId) },
            persist = { cache.replaceActivityPreviews(cityId, it) },
        )

    fun activityIdeas(cityId: String): CacheFirstRepository<List<CachedActivityIdea>> =
        CacheFirstRepository(
            scope = scope,
            cache = cache.observeActivityIdeas(cityId),
            nowEpochMillis = nowEpochMillis,
            isEmpty = { it.isEmpty() },
            refreshFromNetwork = { remote.loadActivityIdeas(cityId) },
            persist = { cache.replaceActivityIdeas(cityId, it) },
        )
}

class MemberContentRepository(
    private val cache: CacheStore,
    private val remote: MemberRemoteDataSource,
    private val scope: CoroutineScope,
    private val nowEpochMillis: () -> Long,
) {
    fun plans(account: CacheAccessScope.Account) = cacheFirst(
        cache.observePlans(account), { remote.loadPlans(account) }, { cache.replacePlans(account, it) },
    )

    fun invitations(account: CacheAccessScope.Account) = cacheFirst(
        cache.observeInvitations(account), { remote.loadInvitations(account) }, { cache.replaceInvitations(account, it) },
    )

    fun messages(member: CacheAccessScope.ActivityMember) = cacheFirst(
        cache.observeMessages(member), { remote.loadMessages(member) }, { cache.replaceMessages(member, it) },
    )

    fun notifications(account: CacheAccessScope.Account) = cacheFirst(
        cache.observeNotifications(account), { remote.loadNotifications(account) }, { cache.replaceNotifications(account, it) },
    )

    suspend fun removeAccess(scope: CacheAccessScope) = cache.deleteScoped(scope)

    private fun <T> cacheFirst(
        rows: Flow<CacheSnapshot<List<T>>>,
        fetch: suspend () -> RefreshResult<List<T>>,
        persist: suspend (List<T>) -> Unit,
    ) = CacheFirstRepository(
        scope = scope,
        cache = rows,
        nowEpochMillis = nowEpochMillis,
        isEmpty = { it.isEmpty() },
        refreshFromNetwork = fetch,
        persist = persist,
    )
}
