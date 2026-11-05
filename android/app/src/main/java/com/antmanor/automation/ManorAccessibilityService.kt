package com.antmanor.automation

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 无障碍服务入口。服务由用户在系统设置中手动开启；本应用不会自动开启它。
 * 服务只读取/点击支付宝界面，不申请网络权限。
 */
class ManorAccessibilityService : AccessibilityService() {

    private var engine: ManorAutomationEngine? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        LogStore.init(this)
        AutomationBridge.attach(this)
        LogStore.append("无障碍服务已连接，等待用户开启运行")
        if (ManorConfig.load(this).enabled) {
            startAutomation()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 状态机按固定间隔主动扫描，不依赖事件内容，避免事件风暴导致重复点击。
    }

    override fun onInterrupt() {
        stopAutomation("无障碍服务被系统中断")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        stopAutomation("无障碍服务已关闭")
        AutomationBridge.detach(this)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        AutomationBridge.detach(this)
        super.onDestroy()
    }

    fun startAutomation() {
        LogStore.init(this)
        val existing = engine
        if (existing != null && existing.isRunning) {
            LogStore.append("自动任务已在运行，忽略重复启动")
            return
        }
        engine = ManorAutomationEngine(this, ManorConfig.load(this)).also { it.start() }
    }

    fun stopAutomation(reason: String) {
        engine?.stop(reason)
        engine = null
    }

    fun onEngineFinished() {
        engine = null
    }

    fun currentRoot(): AccessibilityNodeInfo? = rootInActiveWindow

    fun back(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)
}
