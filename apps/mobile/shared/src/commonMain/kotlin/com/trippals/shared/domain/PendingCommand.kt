package com.trippals.shared.domain

/** A durable, safe-to-retry user action. It is never a server-side fact. */
data class PendingCommand(
    val id: String,
    val owner: CacheAccessScope.Account,
    val kind: CommandKind,
    val payload: String,
    val payloadHash: String,
    val idempotencyKey: String,
    val createdAtEpochMillis: Long,
    val sequence: Long,
    val dependsOnCommandIds: Set<String> = emptySet(),
    val retryCount: Int = 0,
    val lastError: CommandError? = null,
    val status: CommandStatus = CommandStatus.Pending,
) {
    init {
        require(id.isNotBlank())
        require(payloadHash.isNotBlank())
        require(idempotencyKey.isNotBlank())
        require(sequence >= 0)
        require(retryCount >= 0)
    }
}

/**
 * Join is an attempt only. The queue deliberately has no reserved/delivered
 * representation: only a server response can make a user Going.
 */
enum class CommandKind {
    SendMessage,
    AttendanceResponse,
    SaveDraft,
    SendInvitations,
    JoinAttempt,
}

enum class CommandStatus {
    Pending,
    Retrying,
    Replaying,
    RequiresReview,
    Failed,
    Succeeded,
}

data class CommandError(
    val code: String,
    val safeMessage: String,
    val correlationId: String? = null,
)

sealed interface CommandPresentation {
    data object Pending : CommandPresentation
    data object Retrying : CommandPresentation
    data object Sending : CommandPresentation
    data object FailedRetryable : CommandPresentation
    data object NeedsReview : CommandPresentation
    data object ServerConfirmed : CommandPresentation
    data object PendingSeatNotReserved : CommandPresentation
}

fun PendingCommand.presentation(): CommandPresentation = when (kind) {
    CommandKind.JoinAttempt -> when (status) {
        CommandStatus.Pending, CommandStatus.Retrying, CommandStatus.Replaying ->
            CommandPresentation.PendingSeatNotReserved
        CommandStatus.RequiresReview -> CommandPresentation.NeedsReview
        CommandStatus.Failed -> CommandPresentation.FailedRetryable
        CommandStatus.Succeeded -> CommandPresentation.ServerConfirmed
    }

    else -> when (status) {
        CommandStatus.Pending -> CommandPresentation.Pending
        CommandStatus.Retrying -> CommandPresentation.Retrying
        CommandStatus.Replaying -> CommandPresentation.Sending
        CommandStatus.RequiresReview -> CommandPresentation.NeedsReview
        CommandStatus.Failed -> CommandPresentation.FailedRetryable
        CommandStatus.Succeeded -> CommandPresentation.ServerConfirmed
    }
}
