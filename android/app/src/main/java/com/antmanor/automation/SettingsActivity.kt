package com.antmanor.automation

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.RadioButton
import android.widget.Switch
import android.widget.Toast

class SettingsActivity : Activity() {

    private lateinit var etDailyTaskLimit: EditText
    private lateinit var etDailyCap: EditText
    private lateinit var etMinInterval: EditText
    private lateinit var etTaskDwell: EditText
    private lateinit var etStartDate: EditText
    private lateinit var etEndDate: EditText
    private lateinit var etTopN: EditText
    private lateinit var etScanInterval: EditText
    private lateinit var etPageTimeout: EditText
    private lateinit var etMaxSteps: EditText
    private lateinit var etLogLines: EditText
    private lateinit var rbSafe: RadioButton
    private lateinit var rbStandard: RadioButton
    private lateinit var switchAutoNavigate: Switch
    private lateinit var btnSave: Button
    private lateinit var btnDefaults: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        LogStore.init(this)

        etDailyTaskLimit = findViewById(R.id.etDailyTaskLimit)
        etDailyCap = findViewById(R.id.etDailyCap)
        etMinInterval = findViewById(R.id.etMinInterval)
        etTaskDwell = findViewById(R.id.etTaskDwell)
        etStartDate = findViewById(R.id.etStartDate)
        etEndDate = findViewById(R.id.etEndDate)
        etTopN = findViewById(R.id.etTopN)
        etScanInterval = findViewById(R.id.etScanInterval)
        etPageTimeout = findViewById(R.id.etPageTimeout)
        etMaxSteps = findViewById(R.id.etMaxSteps)
        etLogLines = findViewById(R.id.etLogLines)
        rbSafe = findViewById(R.id.rbSafe)
        rbStandard = findViewById(R.id.rbStandard)
        switchAutoNavigate = findViewById(R.id.switchAutoNavigate)
        btnSave = findViewById(R.id.btnSave)
        btnDefaults = findViewById(R.id.btnDefaults)

        fill(ManorConfig.load(this))

        btnSave.setOnClickListener { save() }
        btnDefaults.setOnClickListener {
            fill(ManorConfig(enabled = ManorConfig.load(this).enabled))
            toast("已填入默认值，请点击保存生效")
        }
    }

    private fun fill(config: ManorConfig) {
        etDailyTaskLimit.setText(config.dailyTaskLimit.toString())
        etDailyCap.setText(config.dailyIntimacyCap.toString())
        etMinInterval.setText(config.minActionIntervalSec.toString())
        etTaskDwell.setText(config.taskDwellSec.toString())
        etStartDate.setText(config.activityStartDate)
        etEndDate.setText(config.activityEndDate)
        etTopN.setText(config.topNThreshold.toString())
        etScanInterval.setText(config.scanIntervalMs.toString())
        etPageTimeout.setText(config.pageTimeoutSec.toString())
        etMaxSteps.setText(config.maxStepsPerRun.toString())
        etLogLines.setText(config.logMaxLines.toString())
        rbSafe.isChecked = config.executionLevel == ManorConfig.LEVEL_SAFE
        rbStandard.isChecked = config.executionLevel == ManorConfig.LEVEL_STANDARD
        switchAutoNavigate.isChecked = config.autoNavigate
    }

    private fun save() {
        val current = ManorConfig.load(this)
        val startRaw = etStartDate.text.toString().trim()
        val endRaw = etEndDate.text.toString().trim()
        if (startRaw.isNotEmpty() && ManorDomain.parseDate(startRaw) == null) {
            toast(getString(R.string.toast_invalid_date))
            return
        }
        if (endRaw.isNotEmpty() && ManorDomain.parseDate(endRaw) == null) {
            toast(getString(R.string.toast_invalid_date))
            return
        }
        val start = ManorDomain.parseDate(startRaw)
        val end = ManorDomain.parseDate(endRaw)
        if (start != null && end != null && start.isAfter(end)) {
            toast("活动开始日期不能晚于结束日期")
            return
        }

        val dailyTasks = readInt(etDailyTaskLimit, "每日任务上限", 1, 50) ?: return
        val dailyCap = readInt(etDailyCap, "每日亲密度上限", 0, 2000) ?: return
        val minInterval = readInt(etMinInterval, "最小操作间隔", 2, 60) ?: return
        val taskDwell = readInt(etTaskDwell, "任务页停留秒数", 3, 60) ?: return
        val topN = readInt(etTopN, "前排阈值", 1, 100_000_000) ?: return
        val scanInterval = readInt(etScanInterval, "扫描间隔", 800, 5000) ?: return
        val pageTimeout = readInt(etPageTimeout, "页面等待超时", 5, 120) ?: return
        val maxSteps = readInt(etMaxSteps, "单次运行最大步数", 10, 2000) ?: return
        val logLines = readInt(etLogLines, "日志保留条数", 50, 500) ?: return

        val saved = ManorConfig(
            enabled = current.enabled,
            autoNavigate = switchAutoNavigate.isChecked,
            executionLevel = if (rbStandard.isChecked) ManorConfig.LEVEL_STANDARD else ManorConfig.LEVEL_SAFE,
            dailyTaskLimit = dailyTasks,
            dailyIntimacyCap = dailyCap,
            minActionIntervalSec = minInterval,
            taskDwellSec = taskDwell,
            activityStartDate = startRaw,
            activityEndDate = endRaw,
            topNThreshold = topN,
            scanIntervalMs = scanInterval.toLong(),
            pageTimeoutSec = pageTimeout,
            maxStepsPerRun = maxSteps,
            logMaxLines = logLines
        )
        ManorConfig.save(this, saved)
        LogStore.setMaxLines(saved.normalized().logMaxLines)
        LogStore.append("参数已保存（总开关状态不变；运行中的任务需重新开始后生效）")
        toast(getString(R.string.toast_saved))
        finish()
    }

    private fun readInt(view: EditText, label: String, min: Int, max: Int): Int? {
        val raw = view.text.toString().trim()
        if (raw.isEmpty()) {
            toast("$label 不能为空")
            return null
        }
        val value = raw.toIntOrNull()
        if (value == null) {
            toast(getString(R.string.toast_invalid_number))
            return null
        }
        if (value < min || value > max) {
            toast("$label 取值范围 $min - $max")
            return null
        }
        return value
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }
}
