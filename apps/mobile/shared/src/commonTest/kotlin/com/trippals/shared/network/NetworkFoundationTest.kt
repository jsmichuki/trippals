package com.trippals.shared.network

import io.ktor.http.HttpMethod
import io.ktor.http.URLProtocol
import io.ktor.http.Url
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.datetime.Instant
import kotlinx.serialization.json.Json

class NetworkFoundationTest {
    @Test
    fun `production refuses clear text endpoints`() {
        assertFailsWith<IllegalArgumentException> {
            ApiEnvironment(
                name = "production",
                apiBaseUrl = Url("http://api.trippals.example"),
                webSocketBaseUrl = Url("wss://api.trippals.example/socket"),
                isProduction = true,
            )
        }
    }

    @Test
    fun `TripPals origin includes the protocol host and port`() {
        val environment = ApiEnvironment(
            name = "development",
            apiBaseUrl = Url("https://api.trippals.example"),
            webSocketBaseUrl = Url("wss://api.trippals.example/socket"),
            isProduction = false,
        )

        assertTrue(environment.isTripPalsApi(Url("https://api.trippals.example/v1/cities")))
        assertTrue(!environment.isTripPalsApi(Url("https://evil.example/v1/cities")))
        assertTrue(!environment.isTripPalsApi(Url("http://api.trippals.example/v1/cities")))
        assertEquals(URLProtocol.HTTPS, environment.apiUrl("/v1/cities").protocol)
    }

    @Test
    fun `mutable retry needs an idempotency key`() {
        assertFailsWith<IllegalArgumentException> {
            ApiRequest(
                method = HttpMethod.Post,
                path = "/v1/activities/id/join",
            )
        }

        val request = mutationRequest(
            method = HttpMethod.Patch,
            path = "/v1/activities/id",
            idempotencyKey = IdempotencyKey("same-command-key"),
            expectedVersion = EntityVersion(4),
        )
        assertEquals("same-command-key", request.idempotencyKey?.value)
        assertEquals(4L, request.expectedVersion?.value)
    }

    @Test
    fun `cursor pages retain ordering and remove repeated server ids`() {
        val current = CursorPage(listOf(Item("a"), Item("b")), Cursor("old"))
        val next = CursorPage(listOf(Item("b"), Item("c")), null)

        val merged = current.appendDistinct(next) { it.id }

        assertEquals(listOf("a", "b", "c"), merged.items.map { it.id })
        assertNull(merged.nextCursor)
    }

    @Test
    fun `event local time follows event zone across DST`() {
        val eventTime = Instant.parse("2026-03-29T00:30:00Z").inEventTimeZone("Europe/Paris")
        assertEquals("2026-03-29T01:30", eventTime.local.toString())

        val afterTransition = Instant.parse("2026-03-29T01:30:00Z").inEventTimeZone("Europe/Paris")
        assertEquals("2026-03-29T03:30", afterTransition.local.toString())
    }

    @Test
    fun `error envelope retains correlation fields and current version`() {
        val envelope = Json.decodeFromString(
            ApiErrorEnvelope.serializer(),
            """{"error":{"code":"version_conflict","message":"changed","fields":{"title":["is required"]},"current":{"version":7}},"meta":{"correlation_id":"corr-7"}}""",
        )

        val problem = envelope.error.toProblem(io.ktor.http.HttpStatusCode.Conflict, envelope.meta.correlationId)
        assertEquals("version_conflict", problem.code)
        assertEquals("corr-7", problem.correlationId)
        assertEquals(listOf("is required"), problem.fieldErrors["title"])
        assertEquals(7L, problem.currentVersion)
    }

    private data class Item(val id: String)
}
