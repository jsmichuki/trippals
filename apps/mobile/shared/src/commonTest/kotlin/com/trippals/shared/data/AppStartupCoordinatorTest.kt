package com.trippals.shared.data

import com.trippals.shared.domain.CacheAccessScope
import com.trippals.shared.domain.CommandError
import com.trippals.shared.domain.CommandKind
import com.trippals.shared.domain.PendingCommand
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AppStartupCoordinatorTest {
    @Test
    fun `startup refreshes session replays before activity refresh and socket reconnect`() = runBlocking {
        val calls = mutableListOf<String>()
        val coordinator = AppStartupCoordinator(
            session = SessionStartup { calls += "session"; true },
            commands = CommandReplayEngine(InMemoryStore(command()), CommandReplayer {
                calls += "replay"
                ReplayOutcome.Succeeded
            }),
            activities = ActivityStateRefresher { calls += "activities" },
            channels = ChannelReconnector { calls += "channels" },
        )

        coordinator.startOrResume()

        assertEquals(listOf("session", "replay", "activities", "channels"), calls)
    }

    @Test
    fun `review required command prevents refresh and reconnect`() = runBlocking {
        val calls = mutableListOf<String>()
        val store = InMemoryStore(command = command())
        val coordinator = AppStartupCoordinator(
            session = SessionStartup { calls += "session"; true },
            commands = CommandReplayEngine(store, CommandReplayer {
                calls += "replay"
                ReplayOutcome.RequiresReview(CommandError("version_conflict", "Review required."))
            }),
            activities = ActivityStateRefresher { calls += "activities" },
            channels = ChannelReconnector { calls += "channels" },
        )

        val result = coordinator.startOrResume()

        assertTrue(result.replay?.stoppedForReview == true)
        assertEquals(listOf("session", "replay"), calls)
    }

    private fun command() = PendingCommand(
        id = "draft",
        owner = CacheAccessScope.Account("account"),
        kind = CommandKind.SaveDraft,
        payload = "encrypted-by-store",
        payloadHash = "hash",
        idempotencyKey = "key",
        createdAtEpochMillis = 1,
        sequence = 1,
    )

    private class InMemoryStore(command: PendingCommand? = null) : PendingCommandStore {
        private var values = command?.let(::listOf) ?: emptyList()

        override fun observe(): Flow<List<PendingCommand>> = emptyFlow()
        override suspend fun list(): List<PendingCommand> = values
        override suspend fun findByIdempotencyKey(idempotencyKey: String) =
            values.firstOrNull { it.idempotencyKey == idempotencyKey }

        override suspend fun upsert(command: PendingCommand) {
            values = values.filterNot { it.id == command.id } + command
        }

        override suspend fun deleteFor(owner: CacheAccessScope.Account) {
            values = values.filterNot { it.owner == owner }
        }
    }
}
