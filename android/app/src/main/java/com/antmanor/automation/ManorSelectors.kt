package com.antmanor.automation

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 页面选择器。默认只使用文案（支付宝 H5 页面几乎没有稳定 resource-id），
 * 但查找顺序固定为 resource-id → text → contentDescription。
 * 如果抓取到稳定 id，可写入 filesDir/manor-selectors.json 覆盖默认值，无需重新编译。
 *
 * 文件示例（字段都可省略）：
 * {
 *   "manorEntryIds": ["xxx:id/yyy"],
 *   "manorEntryTexts": ["蚂蚁庄园"],
 *   "familyEntryTexts": ["家庭"],
 *   "taskTodoActions": ["去完成"],
 *   "taskClaimActions": ["领取"],
 *   "skipKeywords": ["支付"],
 *   "riskKeywords": ["滑块"]
 * }
 */
data class ManorSelectors(
    val manorEntryIds: List<String> = emptyList(),
    val manorEntryTexts: List<String> = listOf("蚂蚁庄园"),
    val familyEntryIds: List<String> = emptyList(),
    val familyEntryTexts: List<String> = listOf("家庭", "家人", "家庭任务", "家庭活动"),
    val familyEntryDescriptions: List<String> = listOf("家庭", "家人"),
    /** 家庭房间页（canvas）：标题「相亲相爱一家人」+ 顶部活动条。 */
    val familyRoomMarkers: List<String> = listOf(
        "相亲相爱一家人", "活动期间亲密度", "每日24点更新任务哦", "攒亲密度得奖励", "我的奖励"
    ),
    /** 亲密度任务抽屉：底部有「每日24点更新任务哦」，任务卡片文案可读。 */
    val familyTaskListMarkers: List<String> = listOf("每日24点更新任务哦", "每日24点更新任务"),
    val taskTodoActions: List<String> = listOf(
        "去完成", "立即完成", "立即去", "去逛逛", "去浏览", "去看看", "去做任务",
        "去签到", "去答题", "去捐蛋", "去请客", "去喂食", "去指派", "去分享", "去攒亲密度"
    ),
    val taskClaimActions: List<String> = listOf(
        "领取", "领取奖励", "立即领取", "去领取", "开心收下", "收下", "一键领取"
    ),
    val inTaskClaimTexts: List<String> = listOf(
        "开心收下", "领取奖励", "领取", "我知道了", "完成"
    ),
    val skipKeywords: List<String> = listOf(
        "捐赠", "公益", "付款", "支付", "实付", "充值", "购买", "下单", "游戏",
        "理财", "保险", "贷款", "借呗", "花呗", "开通", "签约", "授权", "绑定",
        // 实测「一起领外卖红包福利」会跳到淘宝「访问被拒绝」页，直接跳过避免误入外部页面
        "外卖", "红包", "淘宝", "天猫", "饿了么",
        // 「每日捐蛋做好事」会进入公益捐赠项目页，需要滚动+选择项目，属于捐赠类，按安全边界跳过
        "捐蛋", "爱心蛋", "捐步"
    ),
    val riskKeywords: List<String> = listOf(
        "安全验证", "人机验证", "滑块验证", "拖动滑块", "请完成验证", "验证码",
        "短信验证", "人脸识别", "访问过于频繁", "操作过于频繁", "账号异常", "环境异常"
    ),
    val doneMarkers: List<String> = listOf("已完成", "已领取", "已收下", "已签到", "明天再来"),
    /** 弹层领取类按钮（优先点击）。 */
    val popupTexts: List<String> = listOf(
        "领取", "领取奖励", "立即领取", "一键领取", "开心收下", "收下",
        "我知道了", "知道了", "确定", "确认", "好的", "继续"
    ),
    /** 弹层关闭类按钮（领取类都不存在时兜底关闭，避免挡住主场景）。 */
    val popupDismissTexts: List<String> = listOf(
        "关闭", "跳过", "取消", "稍后再说", "下次再说", "暂不"
    ),
    /** 答题页识别标记（不能用泛化的「答题」，任务页会有「去答题」按钮）。 */
    val quizMarkers: List<String> = listOf("题目来源", "答答星球"),
    /** 答题预告/题库页（只展示题目与「看答案」，没有可作答选项），直接返回即可。 */
    val quizPreviewMarkers: List<String> = listOf("看答案", "明日题目"),
    /** 饲料任务页识别标记。 */
    val taskPageMarkers: List<String> = listOf("饲料任务", "庄园小课堂", "去答题", "去完成"),
    /** 任务页里的答题入口按钮。 */
    val quizEntryTexts: List<String> = listOf("去答题"),
    /** canvas 主场景里仅有的系统文案，出现其他文案说明不是主场景。 */
    val canvasChromeTexts: List<String> = listOf("蚂蚁庄园", "返回", "更多", "关闭", "分享"),
    /** 答题选项常见文案。 */
    val quizOptionWords: List<String> = listOf(
        "更高", "更低", "是的", "不是", "正确", "错误", "对", "错",
        "A", "B", "C", "D", "以上都是", "以上都不是"
    ),
    /** 庄园主场景的标题文案（canvas 页只有标题可读）。 */
    val manorTitleTexts: List<String> = listOf("蚂蚁庄园")
) {

    companion object {
        const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
        const val OVERRIDE_FILE = "manor-selectors.json"

        fun load(context: Context): ManorSelectors {
            val defaults = ManorSelectors()
            val external = context.getExternalFilesDir(null)?.let { File(it, OVERRIDE_FILE) }
            val internal = File(context.applicationContext.filesDir, OVERRIDE_FILE)
            val file = listOfNotNull(external, internal).firstOrNull { it.exists() } ?: return defaults
            return runCatching {
                val json = JSONObject(file.readText())
                defaults.copy(
                    manorEntryIds = json.stringList("manorEntryIds", defaults.manorEntryIds),
                    manorEntryTexts = json.stringList("manorEntryTexts", defaults.manorEntryTexts),
                    familyEntryIds = json.stringList("familyEntryIds", defaults.familyEntryIds),
                    familyEntryTexts = json.stringList("familyEntryTexts", defaults.familyEntryTexts),
                    familyEntryDescriptions = json.stringList(
                        "familyEntryDescriptions",
                        defaults.familyEntryDescriptions
                    ),
                    familyRoomMarkers = json.stringList("familyRoomMarkers", defaults.familyRoomMarkers),
                    familyTaskListMarkers = json.stringList(
                        "familyTaskListMarkers",
                        defaults.familyTaskListMarkers
                    ),
                    taskTodoActions = json.stringList("taskTodoActions", defaults.taskTodoActions),
                    taskClaimActions = json.stringList("taskClaimActions", defaults.taskClaimActions),
                    inTaskClaimTexts = json.stringList("inTaskClaimTexts", defaults.inTaskClaimTexts),
                    skipKeywords = json.stringList("skipKeywords", defaults.skipKeywords),
                    riskKeywords = json.stringList("riskKeywords", defaults.riskKeywords),
                    doneMarkers = json.stringList("doneMarkers", defaults.doneMarkers)
                )
            }.getOrElse {
                LogStore.append("选择器配置文件解析失败，已回退默认值：${it.message}")
                defaults
            }
        }

        private fun JSONObject.stringList(key: String, fallback: List<String>): List<String> {
            val array = optJSONArray(key) ?: return fallback
            val result = ArrayList<String>(array.length())
            for (i in 0 until array.length()) {
                val value = array.optString(i, "").trim()
                if (value.isNotEmpty()) result.add(value)
            }
            return if (result.isEmpty()) fallback else result
        }
    }
}

object RiskGuard {

    /** 命中任意风控关键词即视为必须立即停止，不尝试任何绕过。 */
    fun hit(texts: List<String>, keywords: List<String>): String? {
        for (text in texts) {
            for (keyword in keywords) {
                if (text.contains(keyword)) return keyword
            }
        }
        return null
    }
}
