package com.antmanor.automation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.view.WindowManager

/**
 * 坐标点击。canvas 页面没有可点击节点，只能靠手势派发。
 * 不需要 FOREGROUND 权限，依赖无障碍服务的 canPerformGestures。
 *
 * 注意：服务里的 resources.displayMetrics 可能不包含底部导航栏（可用高度 < 物理高度），
 * 用 maximumWindowMetrics 取整块屏幕，否则 0.9 这类底部比例会点到导航栏上方。
 * 真机实测：SM-F741N 物理高度 2640，服务 displayMetrics 只有约 2400。
 */
object GestureTap {

    fun tapRatio(service: AccessibilityService, xRatio: Float, yRatio: Float): Boolean {
        val bounds = screenBounds(service)
        val width = bounds.first
        val height = bounds.second
        if (width <= 0 || height <= 0) return false
        val x = (width * xRatio).coerceIn(1f, width - 1f)
        val y = (height * yRatio).coerceIn(1f, height - 1f)
        return tap(service, x, y)
    }

    private fun screenBounds(service: AccessibilityService): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val wm = service.getSystemService(WindowManager::class.java)
            val bounds = wm.maximumWindowMetrics.bounds
            if (bounds.width() > 0 && bounds.height() > 0) {
                return bounds.width() to bounds.height()
            }
        }
        val metrics = service.resources.displayMetrics
        return metrics.widthPixels to metrics.heightPixels
    }

    fun tap(service: AccessibilityService, x: Float, y: Float): Boolean {
        return runCatching {
            val path = Path().apply { moveTo(x, y) }
            val gesture = GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0L, 90L))
                .build()
            service.dispatchGesture(gesture, null, null)
        }.getOrDefault(false)
    }
}
