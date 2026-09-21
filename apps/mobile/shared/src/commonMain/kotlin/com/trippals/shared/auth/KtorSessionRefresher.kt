package com.trippals.shared.auth

import com.trippals.shared.network.ApiEnvironment
import com.trippals.shared.network.ApiErrorEnvelope
import com.trippals.shared.network.ApiProblem
import com.trippals.shared.network.IdempotencyKeyFactory
import com.trippals.shared.network.toProblem
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Direct, unauthenticated call used by [TokenRefreshCoordinator]; it never sends a bearer token. */
class KtorSessionRefresher(
    private val httpClient: HttpClient,
    private val environment: ApiEnvironment,
    private val idempotencyKeys: IdempotencyKeyFactory,
) : SessionRefresher {
    override suspend fun refresh(refreshToken: String): RefreshResult = try {
        val response = httpClient.post(environment.apiUrl("/v1/auth/refresh")) {
            contentType(ContentType.Application.Json)
            header("Idempotency-Key", idempotencyKeys.newKey().value)
            setBody(RefreshRequestWire(refreshToken))
        }
        val correlationId = response.headers["X-Correlation-Id"]

        when {
            response.status.value in 200..299 -> {
                val body = response.body<RefreshEnvelopeWire>()
                RefreshResult.Success(SessionTokens(body.data.accessToken, body.data.refreshToken))
            }

            response.status.value in setOf(400, 401, 403) -> {
                val error = response.body<ApiErrorEnvelope>()
                RefreshResult.Rejected(error.error.toProblem(response.status, correlationId ?: error.meta.correlationId))
            }

            else -> {
                val error = runCatching { response.body<ApiErrorEnvelope>() }.getOrNull()
                RefreshResult.RetryableFailure(
                    error?.error?.toProblem(response.status, correlationId ?: error.meta.correlationId),
                )
            }
        }
    } catch (cause: Throwable) {
        RefreshResult.RetryableFailure(cause = cause)
    }
}

@Serializable
private data class RefreshRequestWire(@SerialName("refresh_token") val refreshToken: String)

@Serializable
private data class RefreshEnvelopeWire(val data: RefreshTokensWire)

@Serializable
private data class RefreshTokensWire(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
)
