package com.antmanor.automation

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import java.util.ArrayDeque

enum class TaskKind { CLAIM, TODO }

data class TaskCandidate(
    val key: String,
    val title: String,
    val actionText: String,
    val kind: TaskKind,
    val targetNode: AccessibilityNodeInfo,
    val blockedReason: String?
)

/**
 * 家庭任务识别。规则移植自 iOS 版：
 * - 已完成/已领取的卡片不再处理；
 * - 需真实出资、授权、游戏充值的任务一律跳过；
 * - 只用页面可见文案判断，不调用任何接口。
 */
object TaskScanner {

    private const val MAX_SCAN_NODES = 1500

    fun scan(root: AccessibilityNodeInfo, selectors: ManorSelectors): List<TaskCandidate> {
        val result = ArrayList<TaskCandidate>()
        val seen = HashSet<String>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var scanned = 0

        while (queue.isNotEmpty() && scanned < MAX_SCAN_NODES) {
            val node = queue.removeFirst()
            scanned++
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }

            val label = NodeUtils.textOf(node) ?: continue
            if (label.length > 12) continue
            val matched = matchAction(label, selectors) ?: continue

            val title = NodeUtils.containerLabel(node, label)
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val key = if (title.isNotBlank()) {
                normalize(title) + "|" + matched.second
            } else {
                matched.second + "|" + bounds.left + "," + bounds.top
            }
            if (!seen.add(key)) continue

            val blocked = blockedReason(title.ifBlank { matched.second }, matched.second, selectors)
            result.add(
                TaskCandidate(
                    key = key,
                    title = title.ifBlank { matched.second },
                    actionText = matched.second,
                    kind = matched.first,
                    targetNode = node,
                    blockedReason = blocked
                )
            )
        }
        return result
    }

    private fun matchAction(label: String, selectors: ManorSelectors): Pair<TaskKind, String>? {
        val text = label.trim()
        selectors.taskClaimActions.firstOrNull { it == text }?.let { return TaskKind.CLAIM to it }
        selectors.taskTodoActions.firstOrNull { it == text }?.let { return TaskKind.TODO to it }
        return null
    }

    private fun blockedReason(title: String, actionText: String, selectors: ManorSelectors): String? {
        val haystack = title + " " + actionText
        for (keyword in selectors.skipKeywords) {
            if (haystack.contains(keyword)) return "包含需支付/授权/充值类关键词「$keyword」"
        }
        return null
    }

    private fun normalize(value: String): String =
        value.replace("\\s+".toRegex(), "").lowercase()
}
