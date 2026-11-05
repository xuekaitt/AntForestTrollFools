package com.antmanor.automation

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings

object AccessibilityHelper {

    fun isServiceEnabled(context: Context): Boolean {
        // 注意：不同 ROM 保存的组件名格式不同（三星存短格式 "包名/.类名"），
        // 必须解析成 ComponentName 再比较，不能直接比对字符串。
        val expected = ComponentName(context, ManorAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { entry ->
            val component = ComponentName.unflattenFromString(entry.trim()) ?: return@any false
            component.packageName == expected.packageName && component.className == expected.className
        }
    }

    fun isConnected(): Boolean = AutomationBridge.isConnected()

    fun openAccessibilitySettings(context: Context) {
        runCatching {
            context.startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }.onFailure {
            LogStore.append("无法打开无障碍设置：${it.message}")
        }
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestIgnoreBatteryOptimizations(context: Context) {
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching {
            context.startActivity(direct)
        }.onFailure {
            runCatching {
                context.startActivity(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }.onFailure { inner ->
                LogStore.append("无法打开电池优化设置：${inner.message}")
            }
        }
    }
}
