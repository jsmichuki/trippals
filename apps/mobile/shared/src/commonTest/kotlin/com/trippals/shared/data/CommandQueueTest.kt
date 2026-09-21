package com.trippals.shared.data

import com.trippals.shared.domain.CacheAccessScope
import com.trippals.shared.domain.CommandError
import com.trippals.shared.domain.CommandKind
import com.trippals.shared.domain.CommandPresentation
import com.trippals.shared.domain.CommandStatus
import com.trippals.shared.domain.PendingCommand
import com.trippals.shared.domain.presentation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class CommandQueueTest {
    @Test
    fun `same idempotency key with another payload is rejected`() = runBlocking {
        val store = MemoryCommandStore()
        val queue = CommandQueue(store)
        queue.enqueue(command(id = "one", idempotencyKey = "key", payloadHash = "hash-a"))

        val result = queue.enqueue(command(id = "two", idempotencyKey = "key", payloadHash = "hash-b"))

        assertIs<EnqueueResult.IdempotencyConflict>(result)
        assertEquals("one", result.existingCommandId)
    }

    @Test
    fun `review result stops ordered replay before dependent action`() = runBlocking {
        val store = MemoryCommandStore()
        val first = command(id = "first", sequence = 1)
        val second = command(id = "second", sequence = 2, dependencies = setOf("first"))
        store.upsert(first)
        store.upsert(second)
        val engine = CommandReplayEngine(store, CommandReplayer {
            ReplayOutcome.RequiresReview(CommandError("version_conflict", "Review the updated activity."))
        })

        val report = engine.replay()

        assertTrue(report.stoppedForReview)
        assertEquals(listOf("first"), report.attemptedCommandIds)
        assertEquals(CommandStatus.RequiresReview, store.byId("first")?.status)
        assertEquals(CommandStatus.Pending, store.byId("second")?.status)
    }

    @Test
    fun `join attempt is never presented as a reservation or delivery`() {
        val join = command(kind = CommandKind.JoinAttempt)

        assertEquals(CommandPresentation.PendingSeatNotReserved, join.presentation())
        assertEquals(
            CommandPresentation.ServerConfirmed,
            join.copy(status = CommandStatus.Succeeded).presentation(),
        )
    }

    private fun command(
        id: String = "command",
        kind: CommandKind = CommandKind.SendMessage,
        idempotencyKey: String = "idempotency-$id",
        payloadHash: String = "hash-$id",
        sequence: Long = 1,
        dependencies: Set<String> = emptySet(),
    ) = PendingCommand(
        id = id,
        owner = CacheAccessScope.Account("account-1"),
        kind = kind,
        payload = "safe payload",
        payloadHash = payloadHash,
        idempotencyKey = idempotencyKey,
        createdAtEpochMillis = 1,
        sequence = sequence,
        dependsOnCommandIds = dependencies,
    )
}

private class MemoryCommandStore : PendingCommandStore {
    private val commands = linkedMapOf<String, PendingCommand>()
    private val state = MutableStateFlow<List<PendingCommand>>(emptyList())

    override fun observe(): Flow<List<PendingCommand>> = state
    override suspend fun list(): List<PendingCommand> = commands.values.toList()
    override suspend fun findByIdempotencyKey(idempotencyKey: String): PendingCommand? =
        commands.values.firstOrNull { it.idempotencyKey == idempotencyKey }

    override suspend fun upsert(command: PendingCommand) {
        commands[command.id] = command
        state.value = commands.values.toList()
    }

    override suspend fun deleteFor(owner: CacheAccessScope.Account) {
        commands.entries.removeAll { it.value.owner == owner }
        state.value = commands.values.toList()
    }

    fun byId(id: String): PendingCommand? = commands[id]
}
