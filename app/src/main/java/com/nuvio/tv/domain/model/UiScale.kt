package com.nuvio.tv.domain.model

object UiScale {
    const val DEFAULT_PERCENT = 100
    val options = listOf(70, 80, 90, 100, 110)

    fun normalize(percent: Int): Int = percent.takeIf { it in options } ?: DEFAULT_PERCENT

    fun factor(percent: Int): Float = normalize(percent) / 100f
}
