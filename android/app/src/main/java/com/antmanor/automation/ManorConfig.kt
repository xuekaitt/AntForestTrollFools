package com.antmanor.automation

import android.content.Context
import android.content.SharedPreferences

/**
 * 本地配置。全部字段只保存在本机 SharedPreferences，不涉及任何网络配置。
 * 总开关默认关闭；必须由用户在主页手动打开。
 */
data class ManorConfig(
    val enabled: Boolean = false,
    val autoNavigate: Boolean = true,
    val executionLevel: String = LEVEL_SAFE,
    val dailyTaskLimit: Int = 10,
    val dailyIntimacyCap: Int = 0,
    val minActionIntervalSec: Int = 5,
    val taskDwellSec: Int = 8,
    val activityStartDate: String = "",
    val activityEndDate: String = "",
    val topNThreshold: Int = 2000000,
    val scanIntervalMs: Long = 1200L,
    val pageTimeoutSec: Int = 20,
    val maxStepsPerRun: Int = 600,
    val logMaxLines: Int = 300
) {

    fun normalized(): ManorConfig = copy(
        dailyTaskLimit = dailyTaskLimit.coerceIn(1, 50),
        dailyIntimacyCap = if (dailyIntimacyCap <= 0) 0 else dailyIntimacyCap.coerceIn(1, 2000),
        minActionIntervalSec = minActionIntervalSec.coerceIn(2, 60),
        taskDwellSec = taskDwellSec.coerceIn(3, 60),
        topNThreshold = if (topNThreshold <= 0) 2000000 else topNThreshold,
        scanIntervalMs = scanIntervalMs.coerceIn(800L, 5000L),
        pageTimeoutSec = pageTimeoutSec.coerceIn(5, 120),
        maxStepsPerRun = maxStepsPerRun.coerceIn(10, 2000),
        logMaxLines = logMaxLines.coerceIn(50, 500),
        executionLevel = if (executionLevel == LEVEL_STANDARD) LEVEL_STANDARD else LEVEL_SAFE,
        activityStartDate = activityStartDate.trim(),
        activityEndDate = activityEndDate.trim()
    )

    companion object {
        const val LEVEL_SAFE = "SAFE"
        const val LEVEL_STANDARD = "STANDARD"

        private const val PREFS_NAME = "manor_config"

        private const val KEY_ENABLED = "enabled"
        private const val KEY_AUTO_NAVIGATE = "autoNavigate"
        private const val KEY_EXECUTION_LEVEL = "executionLevel"
        private const val KEY_DAILY_TASK_LIMIT = "dailyTaskLimit"
        private const val KEY_DAILY_CAP = "dailyIntimacyCap"
        private const val KEY_MIN_INTERVAL = "minActionIntervalSec"
        private const val KEY_TASK_DWELL = "taskDwellSec"
        private const val KEY_START_DATE = "activityStartDate"
        private const val KEY_END_DATE = "activityEndDate"
        private const val KEY_TOP_N = "topNThreshold"
        private const val KEY_SCAN_INTERVAL = "scanIntervalMs"
        private const val KEY_PAGE_TIMEOUT = "pageTimeoutSec"
        private const val KEY_MAX_STEPS = "maxStepsPerRun"
        private const val KEY_LOG_LINES = "logMaxLines"

        fun prefs(context: Context): SharedPreferences =
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        fun load(context: Context): ManorConfig {
            val p = prefs(context)
            return ManorConfig(
                enabled = p.getBoolean(KEY_ENABLED, false),
                autoNavigate = p.getBoolean(KEY_AUTO_NAVIGATE, true),
                executionLevel = p.getString(KEY_EXECUTION_LEVEL, LEVEL_SAFE) ?: LEVEL_SAFE,
                dailyTaskLimit = p.getInt(KEY_DAILY_TASK_LIMIT, 10),
                dailyIntimacyCap = p.getInt(KEY_DAILY_CAP, 0),
                minActionIntervalSec = p.getInt(KEY_MIN_INTERVAL, 5),
                taskDwellSec = p.getInt(KEY_TASK_DWELL, 8),
                activityStartDate = p.getString(KEY_START_DATE, "") ?: "",
                activityEndDate = p.getString(KEY_END_DATE, "") ?: "",
                topNThreshold = p.getInt(KEY_TOP_N, 2000000),
                scanIntervalMs = p.getLong(KEY_SCAN_INTERVAL, 1200L),
                pageTimeoutSec = p.getInt(KEY_PAGE_TIMEOUT, 20),
                maxStepsPerRun = p.getInt(KEY_MAX_STEPS, 600),
                logMaxLines = p.getInt(KEY_LOG_LINES, 300)
            ).normalized()
        }

        fun save(context: Context, config: ManorConfig) {
            val c = config.normalized()
            prefs(context).edit()
                .putBoolean(KEY_ENABLED, c.enabled)
                .putBoolean(KEY_AUTO_NAVIGATE, c.autoNavigate)
                .putString(KEY_EXECUTION_LEVEL, c.executionLevel)
                .putInt(KEY_DAILY_TASK_LIMIT, c.dailyTaskLimit)
                .putInt(KEY_DAILY_CAP, c.dailyIntimacyCap)
                .putInt(KEY_MIN_INTERVAL, c.minActionIntervalSec)
                .putInt(KEY_TASK_DWELL, c.taskDwellSec)
                .putString(KEY_START_DATE, c.activityStartDate)
                .putString(KEY_END_DATE, c.activityEndDate)
                .putInt(KEY_TOP_N, c.topNThreshold)
                .putLong(KEY_SCAN_INTERVAL, c.scanIntervalMs)
                .putInt(KEY_PAGE_TIMEOUT, c.pageTimeoutSec)
                .putInt(KEY_MAX_STEPS, c.maxStepsPerRun)
                .putInt(KEY_LOG_LINES, c.logMaxLines)
                .apply()
        }

        fun setEnabled(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        }
    }
}
