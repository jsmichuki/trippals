package com.trippals.shared.domain

/**
 * Explicit presentation state for a cache-first repository.
 * `data` remains available during refresh and retryable failures so a screen
 * never has to misrepresent cached content as current network content.
 */
data class RepositoryState<T>(
    val data: T? = null,
    val phase: LoadPhase = LoadPhase.Initial,
    val freshness: CacheFreshness = CacheFreshness.Unavailable,
    val error: RepositoryError? = null,
) {
    val isLoading: Boolean get() = phase == LoadPhase.Initial || phase == LoadPhase.Refreshing
    val isEmpty: Boolean get() = phase == LoadPhase.Empty
}

enum class LoadPhase {
    Initial,
    Refreshing,
    Content,
    Empty,
}

enum class CacheFreshness {
    Unavailable,
    Fresh,
    Stale,
}

data class RepositoryError(
    val code: String,
    val safeMessage: String,
    val retryable: Boolean,
    val correlationId: String? = null,
)
