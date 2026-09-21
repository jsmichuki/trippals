package com.trippals.shared.network

@JvmInline
value class Cursor(val value: String) {
    init {
        require(value.isNotBlank()) { "Cursor cannot be blank" }
    }
}

data class CursorPage<T>(
    val items: List<T>,
    val nextCursor: Cursor?,
)

/** Keeps server ordering and removes only duplicate server IDs seen across cursor pages. */
fun <T> CursorPage<T>.appendDistinct(
    next: CursorPage<T>,
    idOf: (T) -> String,
): CursorPage<T> {
    val seen = items.asSequence().map(idOf).toMutableSet()
    val merged = buildList {
        addAll(items)
        next.items.forEach { item -> if (seen.add(idOf(item))) add(item) }
    }
    return CursorPage(merged, next.nextCursor)
}

fun Cursor?.asQueryParameter(): String? = this?.value
