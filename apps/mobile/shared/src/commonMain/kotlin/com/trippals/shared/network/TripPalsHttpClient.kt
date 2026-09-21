package com.trippals.shared.network

import com.trippals.shared.auth.RefreshOutcome
import com.trippals.shared.auth.SecureSessionStore
import com.trippals.shared.auth.TokenRefreshCoordinator
import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngineFactory
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.request.url
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.http.takeFrom
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import io.ktor.serialization.kotlinx.json.json

fun interface CorrelationIdFactory {
    fun newId(): String
}

/** Shared Ktor configuration; platform code supplies OkHttp or Darwin as the engine. */
fun createTripPalsKtorClient(engine: HttpClientEngineFactory<*>): HttpClient = HttpClient(engine) {
    expectSuccess = false
    install(ContentNegotiation) {
        json(Json { ignoreUnknownKeys = true; explicitNulls = false })
    }
    install(WebSockets)
}

/** Diagnostics must use this shape, never raw headers or request/response bodies. */
data class SafeHttpDiagnostic(
    val method: String,
    val path: String,
    val status: Int?,
    val correlationId: String?,
)

/**
 * The sole shared HTTP boundary. It deliberately adds Authorization itself rather
 * than using a global default header, preventing credentials from leaving the
 * configured TripPals origin. Diagnostics should consume [ApiResult] only: this
 * class neither logs headers nor request/response bodies.
 */
class TripPalsHttpClient(
    private val httpClient: HttpClient,
    private val environment: ApiEnvironment,
    private val sessions: SecureSessionStore,
    private val refreshCoordinator: TokenRefreshCoordinator,
    private val correlationIds: CorrelationIdFactory,
    private val json: Json = Json { ignoreUnknownKeys = true; explicitNulls = false },
) {
    suspend fun <T> execute(request: ApiRequest, serializer: KSerializer<T>): ApiResult<T> {
        val accessToken = if (request.requiresAuthentication) sessions.accessToken() else null
        val first = executeOnce(request, accessToken, serializer)

        if (first !is ApiResult.Authentication || !request.requiresAuthentication || !request.mayRetryAfterRefresh) {
            return first
        }

        return when (val refresh = refreshCoordinator.refreshAfterUnauthorized(accessToken)) {
            RefreshOutcome.AlreadyRefreshed,
            RefreshOutcome.Refreshed,
            -> executeOnce(request, sessions.accessToken(), serializer)

            is RefreshOutcome.Rejected -> ApiResult.Authentication(
                refresh.problem ?: ApiProblem(
                    status = HttpStatusCode.Unauthorized.value,
                    code = "session_expired",
                    safeMessage = "Your session has ended. Please sign in again.",
                    correlationId = null,
                ),
            )

            is RefreshOutcome.RetryableFailure -> ApiResult.Offline(refresh.cause)
        }
    }

    private suspend fun <T> executeOnce(
        request: ApiRequest,
        accessToken: String?,
        serializer: KSerializer<T>,
    ): ApiResult<T> = try {
        val response = httpClient.request {
            url.takeFrom(environment.apiUrl(request.path))
            method = request.method
            request.query.forEach { (name, value) -> url.parameters.append(name, value) }
            applyTripPalsHeaders(request, accessToken)
            request.body?.let {
                contentType(ContentType.Application.Json)
                setBody(it)
            }
        }
        response.toApiResult(serializer)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (cause: Throwable) {
        ApiResult.Offline(cause)
    }

    private fun HttpRequestBuilder.applyTripPalsHeaders(request: ApiRequest, accessToken: String?) {
        check(environment.isTripPalsApi(url.build())) { "Refusing to attach TripPals headers to another origin" }
        header("X-Correlation-Id", correlationIds.newId())
        request.idempotencyKey?.let { header("Idempotency-Key", it.value) }
        request.expectedVersion?.let { header(HttpHeaders.IfMatch, it.value.toString()) }
        if (request.requiresAuthentication && accessToken != null) {
            header(HttpHeaders.Authorization, "Bearer $accessToken")
        }
    }

    private suspend fun <T> HttpResponse.toApiResult(serializer: KSerializer<T>): ApiResult<T> {
        val correlationId = headers["X-Correlation-Id"]
        if (status.value in 200..299) {
            return try {
                val envelope = json.decodeFromString(ApiEnvelope.serializer(serializer), bodyAsText())
                ApiResult.Success(
                    value = envelope.data,
                    correlationId = correlationId ?: envelope.meta.correlationId,
                    nextCursor = envelope.meta.nextCursor?.takeIf(String::isNotBlank)?.let(::Cursor),
                )
            } catch (cause: Throwable) {
                ApiResult.Unexpected(cause = cause)
            }
        }

        val wireError = runCatching { json.decodeFromString(ApiErrorEnvelope.serializer(), bodyAsText()) }.getOrNull()
        val problem = wireError?.error?.toProblem(status, correlationId ?: wireError.meta.correlationId)
            ?: ApiProblem(
                status = status.value,
                code = "http_${status.value}",
                safeMessage = "The server could not process this request.",
                correlationId = correlationId,
            )

        return when (status.value) {
            400, 422 -> ApiResult.Validation(problem)
            401 -> ApiResult.Authentication(problem)
            403 -> ApiResult.Authorization(problem)
            409 -> ApiResult.Conflict(problem)
            429 -> ApiResult.RateLimited(problem, headers[HttpHeaders.RetryAfter]?.toLongOrNull())
            else -> ApiResult.Unexpected(problem)
        }
    }
}

/** Convenience overload for DTOs with generated Kotlin Serialization serializers. */
suspend inline fun <reified T> TripPalsHttpClient.execute(request: ApiRequest): ApiResult<T> =
    execute(request, kotlinx.serialization.serializer())
