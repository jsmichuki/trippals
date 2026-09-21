package com.trippals.shared.network

import io.ktor.http.HttpStatusCode
import kotlinx.serialization.json.JsonObject

sealed interface ApiResult<out T> {
    data class Success<T>(
        val value: T,
        val correlationId: String?,
        val nextCursor: Cursor? = null,
    ) : ApiResult<T>

    data class Validation(val problem: ApiProblem) : ApiResult<Nothing>
    data class Authentication(val problem: ApiProblem) : ApiResult<Nothing>
    data class Authorization(val problem: ApiProblem) : ApiResult<Nothing>
    data class Conflict(val problem: ApiProblem) : ApiResult<Nothing>
    data class RateLimited(val problem: ApiProblem, val retryAfterSeconds: Long?) : ApiResult<Nothing>
    data class Offline(val cause: Throwable? = null) : ApiResult<Nothing>
    data class Unexpected(val problem: ApiProblem? = null, val cause: Throwable? = null) : ApiResult<Nothing>
}

/** Structured error data for presentation and telemetry; never contains request credentials or bodies. */
data class ApiProblem(
    val status: Int,
    val code: String,
    val safeMessage: String,
    val correlationId: String?,
    val fieldErrors: Map<String, List<String>> = emptyMap(),
    val current: JsonObject? = null,
    val currentVersion: Long? = null,
)

internal fun ApiErrorWire.toProblem(status: HttpStatusCode, correlationId: String?): ApiProblem =
    ApiProblem(
        status = status.value,
        code = code,
        safeMessage = message,
        correlationId = correlationId,
        fieldErrors = fields,
        current = current,
        currentVersion = currentVersion,
    )
