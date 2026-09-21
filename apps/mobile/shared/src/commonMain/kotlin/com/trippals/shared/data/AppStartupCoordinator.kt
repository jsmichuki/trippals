package com.trippals.shared.data

/**
 * Coordinates the safe startup order. Each collaborator is injected by native
 * composition so common code never imports lifecycle, network, or socket APIs.
 */
fun interface SessionStartup {
    /** Refreshes/restores the secure session, returning false after a terminal rejection. */
    suspend fun restoreAndRefresh(): Boolean
}

fun interface ActivityStateRefresher {
    /** Fetches currently relevant activity state after command replay. */
    suspend fun refreshCurrentState()
}

fun interface ChannelReconnector {
    /** Connects only after session restoration and replay reconciliation. */
    suspend fun reconnect()
}

data class StartupResult(
    val sessionRestored: Boolean,
    val replay: ReplayReport? = null,
)

/**
 * Queue replay precedes socket reconnect so live events are reconciled against
 * persisted command outcomes. A review-required command suppresses subsequent
 * refresh/reconnect, leaving the UI an explicit review state.
 */
class AppStartupCoordinator(
    private val session: SessionStartup,
    private val commands: CommandReplayEngine,
    private val activities: ActivityStateRefresher,
    private val channels: ChannelReconnector,
) {
    suspend fun startOrResume(): StartupResult {
        if (!session.restoreAndRefresh()) return StartupResult(sessionRestored = false)

        val replay = commands.replay()
        if (replay.stoppedForReview) return StartupResult(sessionRestored = true, replay = replay)

        activities.refreshCurrentState()
        channels.reconnect()
        return StartupResult(sessionRestored = true, replay = replay)
    }
}
