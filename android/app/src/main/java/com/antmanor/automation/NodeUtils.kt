package com.antmanor.automation

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import java.util.ArrayDeque

object NodeUtils {

    private const val MAX_SCAN_NODES = 1500

    fun textOf(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val text = node.text?.toString()?.replace("\u200B", "")?.trim()
        if (!text.isNullOrEmpty()) return text
        val description = node.contentDescription?.toString()?.replace("\u200B", "")?.trim()
        return if (!description.isNullOrEmpty()) description else null
    }

    fun labelOf(node: AccessibilityNodeInfo?): String = textOf(node) ?: ""

    fun collectTexts(root: AccessibilityNodeInfo, limit: Int = 300): List<String> {
        val result = LinkedHashSet<String>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var scanned = 0
        while (queue.isNotEmpty() && scanned < MAX_SCAN_NODES && result.size < limit) {
            val node = queue.removeFirst()
            scanned++
            val label = textOf(node)
            if (!label.isNullOrBlank() && label.length <= 120) {
                result.add(label)
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return result.toList()
    }

    /** 固定降级顺序：resource-id → text → contentDescription。 */
    fun findFirst(
        root: AccessibilityNodeInfo,
        resourceIds: List<String>,
        texts: List<String>,
        descriptions: List<String>,
        exactText: Boolean = false
    ): AccessibilityNodeInfo? {
        if (resourceIds.isNotEmpty()) {
            findByResourceIds(root, resourceIds)?.let { return it }
        }
        if (texts.isNotEmpty()) {
            findByTexts(root, texts, exactText)?.let { return it }
        }
        if (descriptions.isNotEmpty()) {
            findByDescriptions(root, descriptions)?.let { return it }
        }
        return null
    }

    fun findByResourceIds(root: AccessibilityNodeInfo, ids: List<String>): AccessibilityNodeInfo? {
        return firstMatch(root) { node ->
            val viewId = node.viewIdResourceName ?: return@firstMatch false
            ids.any { it == viewId || viewId.endsWith(":$it") || viewId.endsWith("/$it") }
        }
    }

    fun findByTexts(
        root: AccessibilityNodeInfo,
        texts: List<String>,
        exact: Boolean = false
    ): AccessibilityNodeInfo? {
        return firstMatch(root) { node ->
            val label = textOf(node) ?: return@firstMatch false
            if (exact) {
                texts.any { label == it }
            } else {
                texts.any { label.contains(it) }
            }
        }
    }

    /** 只比较节点自身的 text，不受 contentDescription 干扰，用于点击弹层按钮。 */
    fun findByExactTexts(root: AccessibilityNodeInfo, texts: List<String>): AccessibilityNodeInfo? {
        return firstMatch(root) { node ->
            val label = node.text?.toString()?.replace("\u200B", "")?.trim() ?: return@firstMatch false
            texts.any { label == it }
        }
    }

    /** 答题页选项：短文本且具备可点击祖先，用于答题类页面兜底。 */
    fun findQuizOption(root: AccessibilityNodeInfo, optionWords: List<String>): AccessibilityNodeInfo? {
        val direct = findByExactTexts(root, optionWords)
        if (direct != null) return direct
        return firstMatch(root) { node ->
            val label = node.text?.toString()?.trim() ?: return@firstMatch false
            if (label.isEmpty() || label.length > 8) return@firstMatch false
            if (!node.isClickable) {
                val parent = node.parent
                if (parent == null || !parent.isClickable) return@firstMatch false
            }
            true
        }
    }

    fun findByDescriptions(root: AccessibilityNodeInfo, descriptions: List<String>): AccessibilityNodeInfo? {
        return firstMatch(root) { node ->
            val desc = node.contentDescription?.toString()?.trim() ?: return@firstMatch false
            descriptions.any { desc.contains(it) }
        }
    }

    /**
     * 支付宝弹层的关闭按钮启发式（参考 Ant-Manor 的 closeDialogIfExist）：
     * 可点击、接近正方形、水平中心与屏幕中心对齐、位于下半屏。
     * 真机实测家庭页「攒亲密度得奖励」弹层的 X 为 90×87，中心 (540,2131)，与规则一致。
     */
    fun findCenterCloseButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val rootBounds = Rect()
        root.getBoundsInScreen(rootBounds)
        val width = rootBounds.width()
        val height = rootBounds.height()
        if (width <= 0 || height <= 0) return null
        return firstMatch(root) { node ->
            if (!node.isClickable || !node.isEnabled) return@firstMatch false
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            if (bounds.width() <= 0 || bounds.height() <= 0) return@firstMatch false
            val rate = bounds.width().toFloat() / bounds.height().toFloat()
            if (rate < 0.9f || rate > 1.1f) return@firstMatch false
            val centerY = bounds.centerY()
            if (centerY <= height * 0.55f) return@firstMatch false
            kotlin.math.abs(bounds.centerX() - width / 2) <= width * 0.03f
        }
    }

    private fun firstMatch(
        root: AccessibilityNodeInfo,
        predicate: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var scanned = 0
        while (queue.isNotEmpty() && scanned < MAX_SCAN_NODES) {
            val node = queue.removeFirst()
            scanned++
            if (predicate(node)) return node
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    fun findClickable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        var current = node
        var depth = 0
        while (current != null && depth < 6) {
            if (current.isClickable && current.isEnabled) return current
            current = current.parent
            depth++
        }
        return node
    }

    /** 向上取容器文案，用于识别任务标题。 */
    fun containerLabel(node: AccessibilityNodeInfo, exclude: String): String {
        var current = node.parent
        var depth = 0
        while (current != null && depth < 4) {
            val label = textOf(current)
            if (!label.isNullOrBlank()) {
                val cleaned = label.replace(exclude, "").trim()
                if (cleaned.length >= 2) return cleaned.take(80)
            }
            current = current.parent
            depth++
        }
        return ""
    }

    fun clickNode(service: AccessibilityService, node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        var current: AccessibilityNodeInfo? = node
        var depth = 0
        var clickable: AccessibilityNodeInfo? = null
        while (current != null && depth < 6) {
            if (current.isClickable && current.isEnabled) {
                clickable = current
                break
            }
            current = current.parent
            depth++
        }
        if (clickable != null && clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            return true
        }
        // 无障碍 ACTION_CLICK 无效时退化为坐标点击（仅点击可见节点边界中心，不做任何自动化脚本注入）
        val target = clickable ?: node
        val bounds = Rect()
        target.getBoundsInScreen(bounds)
        if (bounds.width() <= 0 || bounds.height() <= 0) return false
        val path = android.graphics.Path().apply {
            moveTo(bounds.centerX().toFloat(), bounds.centerY().toFloat())
        }
        val gesture = android.accessibilityservice.GestureDescription.Builder()
            .addStroke(
                android.accessibilityservice.GestureDescription.StrokeDescription(path, 0L, 120L)
            )
            .build()
        return service.dispatchGesture(gesture, null, null)
    }
}
