package com.trippals.shared.domain

/**
 * The authorization boundary that was in effect when a local record was saved.
 *
 * A cache scope is deliberately not inferred from the current UI. Private rows
 * must be removed or re-scoped when the server changes access.
 */
sealed interface CacheAccessScope {
    val storageKey: String

    data object Public : CacheAccessScope {
        override val storageKey: String = "public"
    }

    data class Account(val accountId: String) : CacheAccessScope {
        override val storageKey: String = "account:$accountId"
    }

    data class ActivityMember(val accountId: String, val activityId: String) : CacheAccessScope {
        override val storageKey: String = "member:$accountId:$activityId"
    }
}

data class CacheMetadata(
    val fetchedAtEpochMillis: Long,
    val serverVersion: String? = null,
    val cursor: String? = null,
    val scope: CacheAccessScope,
    val expiresAtEpochMillis: Long? = null,
) {
    fun isStale(nowEpochMillis: Long): Boolean =
        expiresAtEpochMillis?.let { nowEpochMillis >= it } ?: false
}

data class DiscoverFilters(
    val startLocalDate: String? = null,
    val endLocalDate: String? = null,
    val categories: Set<String> = emptySet(),
)

data class BrowsePreference(
    val selectedCityId: String?,
    val filters: DiscoverFilters = DiscoverFilters(),
    val metadata: CacheMetadata,
)

/** Scheduled activity and an activity idea are intentionally distinct cache types. */
data class CachedActivityPreview(
    val id: String,
    val cityId: String,
    val title: String,
    val category: String,
    val startAtUtc: String,
    val endAtUtc: String,
    val ianaTimezone: String,
    val status: String,
    val metadata: CacheMetadata,
)

data class CachedActivityIdea(
    val id: String,
    val cityId: String,
    val title: String,
    val category: String,
    val description: String,
    val metadata: CacheMetadata,
)

data class CachedPlanSummary(
    val activityId: String,
    val section: String,
    val title: String,
    val status: String,
    val startAtUtc: String?,
    val ianaTimezone: String?,
    val metadata: CacheMetadata,
)

data class CachedInvitationSummary(
    val invitationId: String,
    val activityId: String,
    val status: String,
    val expiresAtUtc: String?,
    val metadata: CacheMetadata,
)

/** The persisted payload is ciphertext; decryption happens only in the database adapter. */
data class CachedMessage(
    val id: String,
    val conversationId: String,
    val activityId: String,
    val senderId: String?,
    val sequence: Long,
    val createdAtUtc: String,
    val body: String,
    val metadata: CacheMetadata,
)

data class CachedNotification(
    val id: String,
    val kind: String,
    val activityId: String?,
    val invitationId: String?,
    val readAtUtc: String?,
    val createdAtUtc: String,
    val metadata: CacheMetadata,
)
