package com.antmanor.automation

/**
 * 进程内单例：连接主页 UI 与无障碍服务实例。
 * 无障碍服务只能由系统绑定，Activity 不能直接启动它，因此通过此桥接传递启动/停止请求。
 */
object AutomationBridge {

    @Volatile
    private var serviceRef: ManorAccessibilityService? = null

    @Volatile
    private var pendingStart = false

    fun attach(service: ManorAccessibilityService) {
        serviceRef = service
        if (pendingStart) {
            pendingStart = false
            service.startAutomation()
        }
    }

    fun detach(service: ManorAccessibilityService) {
        if (serviceRef === service) {
            serviceRef = null
        }
    }

    fun service(): ManorAccessibilityService? = serviceRef

    fun isConnected(): Boolean = serviceRef != null

    /** 返回 false 表示服务未连接，此时记录待启动，服务连接后自动开始。 */
    fun requestStart(): Boolean {
        val service = serviceRef
        if (service == null) {
            pendingStart = true
            return false
        }
        pendingStart = false
        service.startAutomation()
        return true
    }

    fun requestStop(reason: String) {
        pendingStart = false
        serviceRef?.stopAutomation(reason)
    }
}
