package com.antmanor.automation

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** 日期与活动期规则，移植自 iOS 版 AntManorIntimacy 的活动期判断。 */
object ManorDomain {

    private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    fun today(): String = LocalDate.now().format(DATE_FORMAT)

    fun parseDate(raw: String): LocalDate? {
        if (raw.isBlank()) return null
        return try {
            LocalDate.parse(raw.trim(), DATE_FORMAT)
        } catch (e: Exception) {
            null
        }
    }

    fun activityActive(config: ManorConfig): Boolean {
        if (!config.enabled) return false
        val today = LocalDate.now()
        val start = parseDate(config.activityStartDate)
        val end = parseDate(config.activityEndDate)
        if (start != null && today.isBefore(start)) return false
        if (end != null && today.isAfter(end)) return false
        return true
    }

    fun activityWindowText(config: ManorConfig): String {
        val start = config.activityStartDate.ifBlank { "?" }
        val end = config.activityEndDate.ifBlank { "?" }
        val state = if (ManorDomain.activityActive(config)) "进行中" else "未激活"
        return "$start ~ $end（$state）"
    }

    fun activityRemainingText(config: ManorConfig): String {
        val today = LocalDate.now()
        val start = parseDate(config.activityStartDate)
        val end = parseDate(config.activityEndDate)
        if (start != null && today.isBefore(start)) {
            val days = ChronoUnit.DAYS.between(today, start)
            return "距开始 ${days} 天（${config.activityStartDate} 起）"
        }
        if (end != null) {
            val days = ChronoUnit.DAYS.between(today, end)
            return if (days >= 0) {
                "剩余 ${days + 1} 天（截至 $end）"
            } else {
                "已结束（$end）"
            }
        }
        return "未配置结束日期"
    }
}
