package com.trippals.shared.data

import com.trippals.shared.domain.CacheAccessScope
import com.trippals.shared.domain.CommandError
import com.trippals.shared.domain.CommandStatus
import com.trippals.shared.domain.PendingCommand
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface PendingCommandStore {
    fun observe(): Flow<List<PendingCommand>>
    suspend fun list(): List<PendingCommand>
    suspend fun findByIdempotencyKey(idempotencyKey: String): PendingCommand?
    suspend fun upsert(command: PendingCommand)
    suspend fun deleteFor(owner: CacheAccessScope.Account)
}

sealed interface EnqueueResult {
    data class Enqueued(val command: PendingCommand) : EnqueueResult
    data class AlreadyQueued(val command: PendingCommand) : EnqueueResult
    data class IdempotencyConflict(val existingCommandId: String) : EnqueueResult
    data class MissingDependency(val dependencyId: String) : EnqueueResult
    data class CrossAccountDependency(val dependencyId: String) : EnqueueResult
}

/** Persists idempotency identity and ordering before a network call is attempted. */
class CommandQueue(private val store: PendingCommandStore) {
    suspend fun enqueue(command: PendingCommand): EnqueueResult {
        val existing = store.findByIdempotencyKey(command.idempotencyKey)
        if (existing != null) {
            return if (existing.payloadHash == command.payloadHash) {
                EnqueueResult.AlreadyQueued(existing)
            } else {
                EnqueueResult.IdempotencyConflict(existing.id)
            }
        }

        val queued = store.list().associateBy { it.id }
        for (dependencyId in command.dependsOnCommandIds) {
            val dependency = queued[dependencyId] ?: return EnqueueResult.MissingDependency(dependencyId)
            if (dependency.owner != command.owner) return EnqueueResult.CrossAccountDependency(dependencyId)
            if (dependency.sequence >= command.sequence) return EnqueueResult.MissingDependency(dependencyId)
        }
        store.upsert(command)
        return EnqueueResult.Enqueued(command)
    }

    suspend fun retry(commandId: String): Boolean {
        val command = store.list().firstOrNull { it.id == commandId } ?: return false
        if (command.status !in setOf(CommandStatus.Failed, CommandStatus.RequiresReview)) return false
        store.upsert(command.copy(status = CommandStatus.Pending, lastError = null))
        return true
    }
}

sealed interface ReplayOutcome {
    data object Succeeded : ReplayOutcome
    data class Retryable(val error: CommandError) : ReplayOutcome
    data class RequiresReview(val error: CommandError) : ReplayOutcome
    data class PermanentFailure(val error: CommandError) : ReplayOutcome
}

fun interface CommandReplayer {
    suspend fun replay(command: PendingCommand): ReplayOutcome
}

data class ReplayReport(
    val attemptedCommandIds: List<String>,
    val stoppedForReview: Boolean,
    val stoppingCommandId: String? = null,
)

/**
 * Serial command replay. An authorization, conflict, terminal-state, or
 * dependency-review result stops the run; continuing could make later actions
 * misleading. Transport implementations classify those server responses as
 * [ReplayOutcome.RequiresReview].
 */
class CommandReplayEngine(
    private val store: PendingCommandStore,
    private val replayer: CommandReplayer,
    private val maxAutomaticRetries: Int = 3,
) {
    private val replayMutex = Mutex()

    suspend fun replay(): ReplayReport = replayMutex.withLock {
        require(maxAutomaticRetries >= 0)
        val commands = store.list().sortedWith(compareBy<PendingCommand> { it.sequence }.thenBy { it.createdAtEpochMillis })
        val commandById = commands.associateBy { it.id }.toMutableMap()
        val attempted = mutableListOf<String>()

        // A process may have died after persistence but before its response.
        commands.filter { it.status == CommandStatus.Replaying }.forEach { command ->
            val recovered = command.copy(status = CommandStatus.Retrying)
            store.upsert(recovered)
            commandById[recovered.id] = recovered
        }

        for (original in commands) {
            val command = commandById.getValue(original.id)
            if (command.status !in setOf(CommandStatus.Pending, CommandStatus.Retrying)) continue

            val unresolved = command.dependsOnCommandIds.firstOrNull { dependencyId ->
                commandById[dependencyId]?.status != CommandStatus.Succeeded
            }
            if (unresolved != null) {
                val dependency = commandById[unresolved]
                if (dependency == null || dependency.status in setOf(CommandStatus.Failed, CommandStatus.RequiresReview)) {
                    val reviewed = command.copy(
                        status = CommandStatus.RequiresReview,
                        lastError = CommandError("dependency_not_ready", "An earlier action needs review."),
                    )
                    store.upsert(reviewed)
                    return@withLock ReplayReport(attempted, true, reviewed.id)
                }
                continue
            }

            val replaying = command.copy(status = CommandStatus.Replaying)
            store.upsert(replaying)
            commandById[command.id] = replaying
            attempted += command.id

            when (val outcome = replayer.replay(replaying)) {
                ReplayOutcome.Succeeded -> {
                    val succeeded = replaying.copy(status = CommandStatus.Succeeded, lastError = null)
                    store.upsert(succeeded)
                    commandById[succeeded.id] = succeeded
                }
                is ReplayOutcome.Retryable -> {
                    val retries = replaying.retryCount + 1
                    val status = if (retries > maxAutomaticRetries) CommandStatus.Failed else CommandStatus.Retrying
                    val updated = replaying.copy(status = status, retryCount = retries, lastError = outcome.error)
                    store.upsert(updated)
                    commandById[updated.id] = updated
                }
                is ReplayOutcome.PermanentFailure -> {
                    val failed = replaying.copy(status = CommandStatus.Failed, lastError = outcome.error)
                    store.upsert(failed)
                    commandById[failed.id] = failed
                }
                is ReplayOutcome.RequiresReview -> {
                    val reviewed = replaying.copy(status = CommandStatus.RequiresReview, lastError = outcome.error)
                    store.upsert(reviewed)
                    return@withLock ReplayReport(attempted, true, reviewed.id)
                }
            }
        }
        ReplayReport(attempted, false)
    }
}
