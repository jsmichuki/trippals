package com.trippals.shared.network

import io.ktor.http.HttpMethod
import kotlinx.serialization.json.JsonElement

data class ApiRequest(
    val method: HttpMethod,
    val path: String,
    val query: Map<String, String> = emptyMap(),
    val body: JsonElement? = null,
    val requiresAuthentication: Boolean = false,
    val idempotencyKey: IdempotencyKey? = null,
    val expectedVersion: EntityVersion? = null,
    /** Only GET/HEAD and idempotency-protected commands may be retried after refresh. */
    val mayRetryAfterRefresh: Boolean = method in setOf(HttpMethod.Get, HttpMethod.Head),
) {
    init {
        require(path.startsWith('/')) { "API paths must start with /" }
        require(method in setOf(HttpMethod.Get, HttpMethod.Head, HttpMethod.Options) || idempotencyKey != null) {
            "Every state-changing TripPals request needs an Idempotency-Key"
        }
        require(!mayRetryAfterRefresh || method in setOf(HttpMethod.Get, HttpMethod.Head) || idempotencyKey != null) {
            "A retried state-changing request needs its original Idempotency-Key"
        }
        require(expectedVersion == null || method == HttpMethod.Patch) {
            "If-Match is reserved for mutable activity PATCH requests"
        }
    }
}

@JvmInline
value class IdempotencyKey(val value: String) {
    init {
        require(value.isNotBlank()) { "Idempotency-Key cannot be blank" }
    }
}

@JvmInline
value class EntityVersion(val value: Long) {
    init {
        require(value >= 0) { "Entity version cannot be negative" }
    }
}

/**
 * Command queues inject a secure UUID/UUIDv7 generator and persist the returned key.
 * The same key is reused only for a retry of the identical command payload.
 */
fun interface IdempotencyKeyFactory {
    fun newKey(): IdempotencyKey
}

fun mutationRequest(
    method: HttpMethod,
    path: String,
    idempotencyKey: IdempotencyKey,
    query: Map<String, String> = emptyMap(),
    body: JsonElement? = null,
    requiresAuthentication: Boolean = true,
    expectedVersion: EntityVersion? = null,
): ApiRequest {
    require(method !in setOf(HttpMethod.Get, HttpMethod.Head, HttpMethod.Options)) {
        "mutationRequest is only for state-changing methods"
    }

    return ApiRequest(
        method = method,
        path = path,
        query = query,
        body = body,
        requiresAuthentication = requiresAuthentication,
        idempotencyKey = idempotencyKey,
        expectedVersion = expectedVersion,
        mayRetryAfterRefresh = true,
    )
}
