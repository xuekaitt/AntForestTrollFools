package com.antmanor.automation

/**
 * 仅从界面文案解析亲密度与排名，不做任何接口请求。
 * 读不到排名时上层显示「未获取」。
 */
object RankParser {

    private val RANK_PATTERNS = listOf(
        Regex("^我的排名[^0-9]{0,8}(\\d{1,9})"),
        Regex("^亲密度排名[^0-9]{0,8}(\\d{1,9})"),
        Regex("^当前排名[^0-9]{0,8}(\\d{1,9})"),
        Regex("^排名[^0-9]{0,8}(\\d{1,9})")
    )

    private val TOTAL_PATTERNS = listOf(
        Regex("^共\\s*(\\d{1,9})\\s*[人名位]"),
        Regex("^总人数[^0-9]{0,6}(\\d{1,9})"),
        Regex("^(\\d{1,9})\\s*人参与")
    )

    private val TODAY_INTIMACY_PATTERNS = listOf(
        Regex("^今日亲密度[^0-9]{0,6}(\\d{1,6})"),
        Regex("^今天亲密度[^0-9]{0,6}(\\d{1,6})"),
        Regex("^今日获得亲密度[^0-9]{0,6}(\\d{1,6})"),
        // 家庭页顶部「活动期间亲密度 7」，真机实测文案
        Regex("^活动期间亲密度[^0-9]{0,6}(\\d{1,6})")
    )

    private val GAIN_PATTERNS = listOf(
        Regex("^\\+\\s*(\\d{1,4})\\s*亲密度"),
        Regex("^亲密度\\s*\\+\\s*(\\d{1,4})"),
        Regex("^获得\\s*(\\d{1,4})\\s*亲密度")
    )

    fun parseRank(texts: List<String>): Pair<Int, Int>? {
        var rank = 0
        var total = 0

        for (pattern in RANK_PATTERNS) {
            for (text in texts) {
                val clean = text.trim()
                if (clean.contains("规则") || clean.contains("奖励") || clean.contains("奖品")) continue
                val value = pattern.find(clean)?.groupValues?.getOrNull(1)?.toIntOrNull()
                if (value != null && value in 1..10_000_000) {
                    rank = value
                    break
                }
            }
            if (rank > 0) break
        }
        if (rank <= 0) return null

        for (pattern in TOTAL_PATTERNS) {
            for (text in texts) {
                val value = pattern.find(text.trim())?.groupValues?.getOrNull(1)?.toIntOrNull()
                if (value != null && value in 1..100_000_000) {
                    total = value
                    break
                }
            }
            if (total > 0) break
        }
        return rank to total
    }

    fun parseTodayIntimacy(texts: List<String>): Int? {
        for (pattern in TODAY_INTIMACY_PATTERNS) {
            for (text in texts) {
                val value = pattern.find(text.trim())?.groupValues?.getOrNull(1)?.toIntOrNull()
                if (value != null && value in 0..10_000) return value
            }
        }
        return null
    }

    fun parseGain(texts: List<String>): Int? {
        for (pattern in GAIN_PATTERNS) {
            for (text in texts) {
                val clean = text.trim()
                // 页面顶部的“今日亲密度”是累计值，不能当成一次 +N 反复累加
                if (clean.contains("今日") || clean.contains("今天") || clean.contains("累计")) continue
                val value = pattern.find(clean)?.groupValues?.getOrNull(1)?.toIntOrNull()
                if (value != null && value in 1..500) return value
            }
        }
        return null
    }
}
