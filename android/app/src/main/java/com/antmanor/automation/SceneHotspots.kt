package com.antmanor.automation

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * 主场景热区。蚂蚁庄园主场景与家庭小屋均为 canvas 渲染，无障碍节点树里没有任何可点击元素，
 * 因此只能按屏幕比例点击固定坐标。
 *
 * 坐标使用归一化比例（0~1），与设备分辨率无关；默认值基于 1080×2640 实机（SM-F741N）标定，
 * 家庭入口实测为底部导航第三个图标（x≈0.405，y≈0.903）。
 * 可在 filesDir/manor-hotspots.json 覆盖，无需重新编译。
 */
data class SceneAction(
    val id: String,
    val label: String,
    val x: Float,
    val y: Float,
    val settleMs: Long = 2200L
)

object SceneHotspots {

    private const val OVERRIDE_FILE = "manor-hotspots.json"

    /** 默认动作队列，按执行顺序排列。家庭页优先，确保亲密度任务先跑。 */
    private val defaultActions: List<SceneAction> = listOf(
        SceneAction("family_room", "进入家庭小屋", 0.405f, 0.903f),
        SceneAction("feed_chicken", "饲料碗投喂", 0.575f, 0.690f),
        SceneAction("daily_feed", "领饲料/答题签到", 0.255f, 0.903f, settleMs = 4000L)
    )

    fun defaults(): List<SceneAction> = defaultActions

    fun load(context: Context): List<SceneAction> {
        val file = File(context.applicationContext.filesDir, OVERRIDE_FILE)
        if (!file.exists()) return defaultActions
        return runCatching {
            val json = JSONObject(file.readText())
            val array = json.optJSONArray("actions") ?: return@runCatching defaultActions
            val result = ArrayList<SceneAction>(array.length())
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val id = item.optString("id", "").trim()
                if (id.isEmpty()) continue
                result.add(
                    SceneAction(
                        id = id,
                        label = item.optString("label", id),
                        x = item.optDouble("x", defaultXOf(id)).toFloat(),
                        y = item.optDouble("y", defaultYOf(id)).toFloat(),
                        settleMs = item.optLong("settleMs", 2200L)
                    )
                )
            }
            if (result.isEmpty()) defaultActions else result
        }.getOrElse {
            LogStore.append("热区配置解析失败，已回退默认值：${it.message}")
            defaultActions
        }
    }

    private fun defaultXOf(id: String): Double =
        defaultActions.firstOrNull { it.id == id }?.x?.toDouble() ?: 0.5

    private fun defaultYOf(id: String): Double =
        defaultActions.firstOrNull { it.id == id }?.y?.toDouble() ?: 0.5
}
