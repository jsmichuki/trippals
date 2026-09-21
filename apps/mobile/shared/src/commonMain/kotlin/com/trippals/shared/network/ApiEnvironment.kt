package com.trippals.shared.network

import io.ktor.http.URLProtocol
import io.ktor.http.Url

/**
 * Non-secret, build-time configuration for the TripPals API and Phoenix socket.
 *
 * Authentication material deliberately does not belong here. Production accepts
 * only TLS endpoints so an accidental clear-text production configuration fails
 * before any request is sent.
 */
data class ApiEnvironment(
    val name: String,
    val apiBaseUrl: Url,
    val webSocketBaseUrl: Url,
    val isProduction: Boolean,
) {
    init {
        require(apiBaseUrl.protocol in setOf(URLProtocol.HTTP, URLProtocol.HTTPS)) {
            "API base URL must use HTTP or HTTPS"
        }
        require(webSocketBaseUrl.protocol in setOf(URLProtocol.WS, URLProtocol.WSS)) {
            "WebSocket base URL must use WS or WSS"
        }
        if (isProduction) {
            require(apiBaseUrl.protocol == URLProtocol.HTTPS) {
                "Production API traffic must use HTTPS"
            }
            require(webSocketBaseUrl.protocol == URLProtocol.WSS) {
                "Production socket traffic must use WSS"
            }
        }
    }

    /** Exact-origin comparison prevents bearer tokens being sent to another host. */
    fun isTripPalsApi(url: Url): Boolean =
        url.protocol == apiBaseUrl.protocol &&
            url.host.equals(apiBaseUrl.host, ignoreCase = true) &&
            url.port == apiBaseUrl.port

    fun apiUrl(path: String): Url = apiBaseUrl.resolvePath(path)

    fun socketUrl(path: String): Url = webSocketBaseUrl.resolvePath(path)
}

private fun Url.resolvePath(path: String): Url {
    require(path.startsWith('/')) { "TripPals paths must start with /" }
    return Url(toString().trimEnd('/') + path)
}
