package com.trippals.shared.data

import com.trippals.shared.domain.CacheFreshness
import com.trippals.shared.domain.CacheMetadata
import com.trippals.shared.domain.LoadPhase
import com.trippals.shared.domain.RepositoryError
import com.trippals.shared.domain.RepositoryState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CacheSnapshot<T>(
    val value: T,
    val metadata: CacheMetadata?,
)

sealed interface RefreshResult<out T> {
    data class Success<T>(val value: T) : RefreshResult<T>
    data class Failure(val error: RepositoryError) : RefreshResult<Nothing>
}

/**
 * Reusable cache-first state holder. It starts collecting cache immediately;
 * callers invoke [refresh] at route entry, pull-to-refresh, resume, or retry.
 */
class CacheFirstRepository<T>(
    scope: CoroutineScope,
    cache: Flow<CacheSnapshot<T>?>,
    private val nowEpochMillis: () -> Long,
    private val isEmpty: (T) -> Boolean,
    private val refreshFromNetwork: suspend () -> RefreshResult<T>,
    private val persist: suspend (T) -> Unit,
) {
    private val mutableState = MutableStateFlow(RepositoryState<T>())
    val state: StateFlow<RepositoryState<T>> = mutableState.asStateFlow()

    init {
        scope.launch {
            cache.collect { snapshot ->
                if (snapshot == null) return@collect
                val phase = if (isEmpty(snapshot.value)) LoadPhase.Empty else LoadPhase.Content
                mutableState.value = mutableState.value.copy(
                    data = snapshot.value,
                    phase = phase,
                    freshness = snapshot.metadata?.let {
                        if (it.isStale(nowEpochMillis())) CacheFreshness.Stale else CacheFreshness.Fresh
                    } ?: CacheFreshness.Unavailable,
                    error = null,
                )
            }
        }
    }

    suspend fun refresh() {
        mutableState.value = mutableState.value.copy(
            phase = LoadPhase.Refreshing,
            error = null,
        )
        when (val result = refreshFromNetwork()) {
            is RefreshResult.Success -> {
                persist(result.value)
                // SQLDelight observation is asynchronous; do not leave the UI in
                // Refreshing while it waits for the post-transaction emission.
                mutableState.value = mutableState.value.copy(
                    data = result.value,
                    phase = if (isEmpty(result.value)) LoadPhase.Empty else LoadPhase.Content,
                    freshness = CacheFreshness.Fresh,
                    error = null,
                )
            }
            is RefreshResult.Failure -> {
                val current = mutableState.value
                mutableState.value = current.copy(
                    phase = if (current.data == null) LoadPhase.Initial else if (isEmpty(current.data)) LoadPhase.Empty else LoadPhase.Content,
                    freshness = if (current.data == null) CacheFreshness.Unavailable else CacheFreshness.Stale,
                    error = result.error,
                )
            }
        }
    }
}
