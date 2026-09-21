package com.trippals.shared.network

import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

/** Event rendering always uses the IANA timezone supplied by the activity response. */
data class EventLocalTime(
    val instant: Instant,
    val zone: TimeZone,
    val local: LocalDateTime,
) {
    val date: LocalDate get() = local.date
}

fun Instant.inEventTimeZone(ianaTimeZone: String): EventLocalTime {
    val zone = TimeZone.of(ianaTimeZone)
    return EventLocalTime(this, zone, toLocalDateTime(zone))
}

/** Local date filters are sent as dates; the API, not the client, resolves DST UTC bounds. */
data class EventDateRange(val start: LocalDate, val endInclusive: LocalDate) {
    init {
        require(start <= endInclusive) { "Event date range cannot be reversed" }
    }
}
