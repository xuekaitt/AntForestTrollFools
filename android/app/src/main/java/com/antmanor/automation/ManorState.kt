package com.antmanor.automation

import android.content.Context
import android.content.SharedPreferences

data class ManorSnapshot(
    val date: String,
    val todayGained: Int,
    val todayTaskCount: Int,
    val submittedCount: Int,
    val rank: Int,
    val rankTotal: Int,
    val rankUpdatedAt: Long,
    val lastRunStatus: String,
    val lastRunAt: Long
)

/**
 * 今日数据与排名持久化。每日自动滚动，逻辑对齐 iOS 版 resetDailyIfNeeded。
 */
class ManorState private constructor(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val lock = Any()

    private var date: String = prefs.getString(KEY_DATE, "") ?: ""
    private var gained: Int = prefs.getInt(KEY_GAINED, 0)
    private var tasks: Int = prefs.getInt(KEY_TASKS, 0)
    private var submitted: MutableSet<String> =
        HashSet(prefs.getStringSet(KEY_SUBMITTED, emptySet()) ?: emptySet())
    private var rank: Int = prefs.getInt(KEY_RANK, 0)
    private var rankTotal: Int = prefs.getInt(KEY_RANK_TOTAL, 0)
    private var rankAt: Long = prefs.getLong(KEY_RANK_AT, 0L)
    private var lastStatus: String = prefs.getString(KEY_LAST_STATUS, "") ?: ""
    private var lastRunAt: Long = prefs.getLong(KEY_LAST_RUN_AT, 0L)

    init {
        rollIfNeeded()
    }

    fun snapshot(): ManorSnapshot = synchronized(lock) {
        rollIfNeeded()
        ManorSnapshot(
            date = date,
            todayGained = gained,
            todayTaskCount = tasks,
            submittedCount = submitted.size,
            rank = rank,
            rankTotal = rankTotal,
            rankUpdatedAt = rankAt,
            lastRunStatus = lastStatus,
            lastRunAt = lastRunAt
        )
    }

    fun markSubmitted(key: String) = synchronized(lock) {
        if (key.isBlank()) return@synchronized
        rollIfNeeded()
        if (submitted.add(key)) {
            persistSubmitted()
        }
    }

    fun isSubmitted(key: String): Boolean = synchronized(lock) {
        rollIfNeeded()
        submitted.contains(key)
    }

    fun recordTaskCompleted() = synchronized(lock) {
        rollIfNeeded()
        tasks += 1
        lastRunAt = System.currentTimeMillis()
        prefs.edit().putInt(KEY_TASKS, tasks).putLong(KEY_LAST_RUN_AT, lastRunAt).apply()
    }

    fun addGained(amount: Int) = synchronized(lock) {
        if (amount <= 0) return@synchronized
        rollIfNeeded()
        gained += amount
        prefs.edit().putInt(KEY_GAINED, gained).apply()
    }

    /** 页面显示「今日亲密度 N」时使用：只增不减，避免回读旧值把数字改小。 */
    fun setGainedAtLeast(value: Int) = synchronized(lock) {
        if (value <= 0) return@synchronized
        rollIfNeeded()
        if (value > gained) {
            gained = value
            prefs.edit().putInt(KEY_GAINED, gained).apply()
        }
    }

    fun setRank(rankValue: Int, total: Int) = synchronized(lock) {
        if (rankValue <= 0) return@synchronized
        rollIfNeeded()
        rank = rankValue
        if (total > 0) rankTotal = total
        rankAt = System.currentTimeMillis()
        prefs.edit()
            .putInt(KEY_RANK, rank)
            .putInt(KEY_RANK_TOTAL, rankTotal)
            .putLong(KEY_RANK_AT, rankAt)
            .apply()
    }

    fun setLastRunStatus(status: String) = synchronized(lock) {
        lastStatus = status
        lastRunAt = System.currentTimeMillis()
        prefs.edit()
            .putString(KEY_LAST_STATUS, status)
            .putLong(KEY_LAST_RUN_AT, lastRunAt)
            .apply()
    }

    fun resetToday() = synchronized(lock) {
        date = ManorDomain.today()
        gained = 0
        tasks = 0
        submitted.clear()
        prefs.edit()
            .putString(KEY_DATE, date)
            .putInt(KEY_GAINED, 0)
            .putInt(KEY_TASKS, 0)
            .putStringSet(KEY_SUBMITTED, emptySet())
            .apply()
    }

    private fun rollIfNeeded() {
        val today = ManorDomain.today()
        if (date != today) {
            date = today
            gained = 0
            tasks = 0
            submitted.clear()
            prefs.edit()
                .putString(KEY_DATE, today)
                .putInt(KEY_GAINED, 0)
                .putInt(KEY_TASKS, 0)
                .putStringSet(KEY_SUBMITTED, emptySet())
                .apply()
        }
    }

    private fun persistSubmitted() {
        prefs.edit().putStringSet(KEY_SUBMITTED, HashSet(submitted)).apply()
    }

    companion object {
        private const val PREFS_NAME = "manor_state"
        private const val KEY_DATE = "date"
        private const val KEY_GAINED = "todayGained"
        private const val KEY_TASKS = "todayTasks"
        private const val KEY_SUBMITTED = "submittedKeys"
        private const val KEY_RANK = "rank"
        private const val KEY_RANK_TOTAL = "rankTotal"
        private const val KEY_RANK_AT = "rankUpdatedAt"
        private const val KEY_LAST_STATUS = "lastRunStatus"
        private const val KEY_LAST_RUN_AT = "lastRunAt"

        @Volatile
        private var instance: ManorState? = null

        fun get(context: Context): ManorState {
            val existing = instance
            if (existing != null) return existing
            return synchronized(this) {
                val current = instance
                if (current != null) {
                    current
                } else {
                    ManorState(context.applicationContext).also { instance = it }
                }
            }
        }
    }
}
