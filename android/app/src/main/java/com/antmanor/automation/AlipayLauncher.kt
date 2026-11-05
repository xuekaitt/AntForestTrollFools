package com.antmanor.automation

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * 打开支付宝并直达蚂蚁庄园。
 *
 * 参考 Ant-Manor（TonyJiangWJ）的做法：不去支付宝首页找入口图标，
 * 而是用官方 H5 的 scheme `alipays://platformapi/startapp?appId=66666674` 直接进入庄园。
 * 首页是 canvas 渲染，入口图标没有文字节点，靠节点查找很容易失败。
 *
 * Android 10 起禁止后台静默启动 Activity，因此优先由前台 Activity（用户点击「开始运行」）发起；
 * 服务侧只做兜底，失败时给出提示。
 */
object AlipayLauncher {

    private const val MANOR_SCHEME = "alipays://platformapi/startapp?appId=66666674"

    fun open(context: Context): Boolean {
        if (openManor(context)) return true
        // scheme 不可用时退回普通启动支付宝首页
        val intent = context.packageManager
            .getLaunchIntentForPackage(ManorSelectors.ALIPAY_PACKAGE)
            ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return start(context, intent)
    }

    /** 直达蚂蚁庄园主场景（appId 66666674）。 */
    fun openManor(context: Context): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(MANOR_SCHEME)).apply {
            setPackage(ManorSelectors.ALIPAY_PACKAGE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        }
        return start(context, intent)
    }

    private fun start(context: Context, intent: Intent): Boolean {
        return runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)
    }
}
