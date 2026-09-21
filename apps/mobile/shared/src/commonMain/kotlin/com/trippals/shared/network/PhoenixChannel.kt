package com.trippals.shared.network

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

sealed interface PhoenixTopic {
    val value: String

    data class Activity(val activityId: String) : PhoenixTopic {
        override val value: String = "activity:$activityId"
    }

    data class Conversation(val conversationId: String) : PhoenixTopic {
        override val value: String = "conversation:$conversationId"
    }
}

/** Phoenix socket frames are sent only after the server authorizes a topic join. */
@Serializable
data class PhoenixFrame(
    @SerialName("join_ref") val joinRef: String? = null,
    val ref: String? = null,
    val topic: String,
    val event: String,
    val payload: JsonObject = JsonObject(emptyMap()),
)

object PhoenixEvents {
    const val Join = "phx_join"
    const val Leave = "phx_leave"
    const val Reply = "phx_reply"
    const val Error = "phx_error"
    const val Close = "phx_close"
}

data class ChannelResume(val cursor: Cursor? = null)

sealed interface ChannelEvent {
    data class Message(val frame: PhoenixFrame) : ChannelEvent
    data class AccessRevoked(val topic: PhoenixTopic, val reason: String?) : ChannelEvent
    data class TransportFailure(val cause: Throwable?) : ChannelEvent
    data object Closed : ChannelEvent
}

/** Transport contract. Implementations must persist/reconcile messages before acknowledging UI delivery. */
interface PhoenixChannelClient {
    suspend fun connect()
    suspend fun join(topic: PhoenixTopic, resume: ChannelResume = ChannelResume())
    suspend fun leave(topic: PhoenixTopic)
    suspend fun send(topic: PhoenixTopic, event: String, payload: JsonObject, clientMessageId: String? = null)
    suspend fun disconnect()
}
