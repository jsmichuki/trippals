package com.trippals.shared.network

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/** Wire-only envelope used by every JSON endpoint under /v1. */
@Serializable
data class ApiEnvelope<T>(
    val data: T,
    val meta: ApiMeta,
)

@Serializable
data class ApiMeta(
    @SerialName("correlation_id") val correlationId: String? = null,
    @SerialName("next_cursor") val nextCursor: String? = null,
)

@Serializable
data class ApiErrorEnvelope(
    val error: ApiErrorWire,
    val meta: ApiMeta,
)

@Serializable
data class ApiErrorWire(
    val code: String,
    // Do not use this server text as UI-control flow. It is retained only for a safe fallback message.
    val message: String,
    val fields: Map<String, List<String>> = emptyMap(),
    val current: JsonObject? = null,
)

val ApiErrorWire.currentVersion: Long?
    get() = current?.get("version")?.jsonPrimitive?.longOrNull

/** JSON payload accepted by generic requests without conflating wire and domain models. */
typealias ApiJson = JsonElement
