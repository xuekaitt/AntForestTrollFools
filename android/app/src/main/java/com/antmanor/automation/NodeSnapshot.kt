package com.antmanor.automation

import android.content.Context
import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import java.io.File
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale

/**
 * 节点快照导出（校准用）。写到应用外部私有目录，不需要存储权限：
 * Android/data/com.antmanor.automation/files/snapshots/
 * 用快照核对 viewId / text 后，可写入 filesDir/manor-selectors.json 覆盖选择器。
 */
object NodeSnapshot {

    private const val MAX_NODES = 3000

    fun export(context: Context, root: AccessibilityNodeInfo?): File? {
        if (root == null) return null
        val timeStamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.getDefault()).format(Date())
        val dir = context.getExternalFilesDir("snapshots") ?: File(context.filesDir, "snapshots")
        if (!dir.exists() && !dir.mkdirs()) return null
        val file = File(dir, "snapshot-$timeStamp.txt")

        val builder = StringBuilder()
        builder.append("# 节点快照 ").append(timeStamp).append('\n')
        builder.append("# package=").append(root.packageName).append('\n')
        builder.append("# 字段：深度 | class | viewId | clickable | text | contentDescription | bounds\n\n")

        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(root to 0)
        var scanned = 0
        while (queue.isNotEmpty() && scanned < MAX_NODES) {
            val (node, depth) = queue.removeFirst()
            scanned++
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val text = node.text?.toString()?.replace("\n", " ") ?: ""
            val desc = node.contentDescription?.toString()?.replace("\n", " ") ?: ""
            builder.append(depth)
                .append(" | ").append(node.className ?: "?")
                .append(" | ").append(node.viewIdResourceName ?: "")
                .append(" | ").append(if (node.isClickable) "clickable" else "")
                .append(" | ").append(text.take(120))
                .append(" | ").append(desc.take(120))
                .append(" | ").append(bounds.toShortString())
                .append('\n')
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it to depth + 1) }
            }
        }

        return runCatching {
            file.writeText(builder.toString())
            LogStore.append("已导出节点快照：${file.absolutePath}")
            file
        }.getOrNull()
    }
}
