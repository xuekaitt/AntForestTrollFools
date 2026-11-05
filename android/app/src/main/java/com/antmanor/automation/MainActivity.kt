package com.antmanor.automation

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.CompoundButton
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {

    private lateinit var tvServiceState: TextView
    private lateinit var tvGuide: TextView
    private lateinit var tvIntimacy: TextView
    private lateinit var tvTasks: TextView
    private lateinit var tvActivity: TextView
    private lateinit var tvRank: TextView
    private lateinit var tvTopN: TextView
    private lateinit var tvLastRun: TextView
    private lateinit var tvLogs: TextView
    private lateinit var switchEnabled: Switch
    private lateinit var btnAccessibility: Button
    private lateinit var btnBattery: Button
    private lateinit var btnStart: Button
    private lateinit var btnStop: Button
    private lateinit var btnSettings: Button
    private lateinit var btnSnapshot: Button
    private lateinit var btnClearLogs: Button

    private val handler = Handler(Looper.getMainLooper())

    private val refreshRunnable = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, 1000L)
        }
    }

    private val masterSwitchListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
        onMasterSwitchChanged(isChecked)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LogStore.init(this)
        StatusNotifier.ensureChannel(this)
        setContentView(R.layout.activity_main)

        tvServiceState = findViewById(R.id.tvServiceState)
        tvGuide = findViewById(R.id.tvGuide)
        tvIntimacy = findViewById(R.id.tvIntimacy)
        tvTasks = findViewById(R.id.tvTasks)
        tvActivity = findViewById(R.id.tvActivity)
        tvRank = findViewById(R.id.tvRank)
        tvTopN = findViewById(R.id.tvTopN)
        tvLastRun = findViewById(R.id.tvLastRun)
        tvLogs = findViewById(R.id.tvLogs)
        switchEnabled = findViewById(R.id.switchEnabled)
        btnAccessibility = findViewById(R.id.btnAccessibility)
        btnBattery = findViewById(R.id.btnBattery)
        btnStart = findViewById(R.id.btnStart)
        btnStop = findViewById(R.id.btnStop)
        btnSettings = findViewById(R.id.btnSettings)
        btnSnapshot = findViewById(R.id.btnSnapshot)
        btnClearLogs = findViewById(R.id.btnClearLogs)

        btnAccessibility.setOnClickListener {
            AccessibilityHelper.openAccessibilitySettings(this)
        }
        btnBattery.setOnClickListener {
            if (AccessibilityHelper.isIgnoringBatteryOptimizations(this)) {
                toast("已在电池优化白名单中")
            } else {
                AccessibilityHelper.requestIgnoreBatteryOptimizations(this)
            }
        }
        switchEnabled.setOnCheckedChangeListener(masterSwitchListener)
        btnStart.setOnClickListener { onStartClicked() }
        btnStop.setOnClickListener {
            AutomationBridge.requestStop("用户手动停止")
            toast(getString(R.string.toast_stopped))
            render()
        }
        btnSettings.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
        btnSnapshot.setOnClickListener { onExportSnapshot() }
        btnClearLogs.setOnClickListener {
            LogStore.clear()
            render()
        }

        requestNotificationPermission()
        showGuideIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        render()
        handler.removeCallbacks(refreshRunnable)
        handler.postDelayed(refreshRunnable, 500L)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(refreshRunnable)
    }

    private fun onMasterSwitchChanged(isChecked: Boolean) {
        ManorConfig.save(this, ManorConfig.load(this).copy(enabled = isChecked))
        if (isChecked) {
            if (!AccessibilityHelper.isServiceEnabled(this)) {
                toast(getString(R.string.accessibility_hint))
                AccessibilityHelper.openAccessibilitySettings(this)
                return
            }
            AutomationBridge.requestStart()
            if (ManorConfig.load(this).autoNavigate) AlipayLauncher.open(this)
            toast(getString(R.string.toast_started))
        } else {
            AutomationBridge.requestStop("总开关关闭")
            StatusNotifier.stop(this)
        }
        render()
    }

    private fun onStartClicked() {
        val config = ManorConfig.load(this)
        if (!config.enabled) {
            toast("请先打开总开关")
            return
        }
        if (!AccessibilityHelper.isServiceEnabled(this)) {
            toast(getString(R.string.accessibility_hint))
            return
        }
        val started = AutomationBridge.requestStart()
        if (started) {
            if (config.autoNavigate) AlipayLauncher.open(this)
            toast(getString(R.string.toast_started))
        } else {
            toast("无障碍服务尚未连接，已记录启动请求；服务连接后自动开始")
        }
        render()
    }

    private fun onExportSnapshot() {
        val root = AutomationBridge.service()?.currentRoot()
        val file = NodeSnapshot.export(this, root)
        if (file == null) {
            toast(getString(R.string.toast_snapshot_failed))
        } else {
            toast(getString(R.string.toast_snapshot_exported, file.absolutePath))
        }
    }

    private fun render() {
        val config = ManorConfig.load(this)
        val snapshot = ManorState.get(this).snapshot()
        val connected = AccessibilityHelper.isConnected()
        val serviceEnabled = AccessibilityHelper.isServiceEnabled(this)

        tvServiceState.text = when {
            connected -> getString(R.string.service_connected)
            serviceEnabled -> getString(R.string.service_enabled)
            else -> getString(R.string.service_not_enabled)
        }

        tvGuide.visibility = if (connected) TextView.GONE else TextView.VISIBLE

        switchEnabled.setOnCheckedChangeListener(null)
        switchEnabled.isChecked = config.enabled
        switchEnabled.setOnCheckedChangeListener(masterSwitchListener)

        val capText = if (config.dailyIntimacyCap > 0) config.dailyIntimacyCap.toString() else "不限"
        tvIntimacy.text = "今日亲密度：+${snapshot.todayGained} / 上限 $capText"
        tvTasks.text =
            "今日任务：${snapshot.todayTaskCount}/${config.dailyTaskLimit}（去重记录 ${snapshot.submittedCount} 项）"
        tvActivity.text = "活动：${ManorDomain.activityRemainingText(config)} · ${ManorDomain.activityWindowText(config)}"

        tvRank.text = if (snapshot.rank > 0) {
            if (snapshot.rankTotal > 0) {
                "当前排名：第 ${snapshot.rank} 名 / 共 ${snapshot.rankTotal}"
            } else {
                "当前排名：第 ${snapshot.rank} 名"
            }
        } else {
            "当前排名：${getString(R.string.value_unknown)}"
        }

        tvTopN.text = if (snapshot.rank > 0) {
            val inTop = snapshot.rank <= config.topNThreshold
            "前 ${config.topNThreshold} 名判断：${if (inTop) "是" else "否"}"
        } else {
            "前 ${config.topNThreshold} 名判断：${getString(R.string.value_unknown)}"
        }

        tvLastRun.text = if (snapshot.lastRunStatus.isBlank()) {
            "最近一次运行：${getString(R.string.value_none)}"
        } else {
            "最近一次运行：${snapshot.lastRunStatus}"
        }

        tvLogs.text = LogStore.recent(200)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
    }

    private fun showGuideIfNeeded() {
        val prefs = getSharedPreferences("ui_prefs", MODE_PRIVATE)
        if (prefs.getBoolean("guide_shown", false)) return
        prefs.edit().putBoolean("guide_shown", true).apply()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.guide_title))
            .setMessage(getString(R.string.guide_body))
            .setPositiveButton(getString(R.string.open_accessibility)) { _, _ ->
                AccessibilityHelper.openAccessibilitySettings(this)
            }
            .setNegativeButton("稍后", null)
            .show()
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    companion object {
        private const val REQUEST_NOTIFICATIONS = 10
    }
}
