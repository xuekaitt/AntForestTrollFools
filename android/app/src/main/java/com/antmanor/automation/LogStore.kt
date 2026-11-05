package com.antmanor.automation

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 本地日志：仅写入应用私有目录，条数受限（默认 300），不联网、不上传。
 */
object LogStore {

    private const val FILE_NAME = "manor-log.txt"
    private const val TIME_PATTERN = "HH:mm:ss"

    private val lock = Any()
    private val lines = ArrayDeque<String>()
    private var maxLines = 300
    private var logFile: File? = null
    private val timeFormat = SimpleDateFormat(TIME_PATTERN, Locale.getDefault())

    fun init(context: Context) {
        synchronized(lock) {
            if (logFile != null) return
            logFile = File(context.applicationContext.filesDir, FILE_NAME)
            maxLines = ManorConfig.load(context).logMaxLines
            val file = logFile
            if (file != null && file.exists()) {
                runCatching {
                    file.readLines().forEach { if (it.isNotBlank()) lines.addLast(it) }
                }
                trimInMemory()
            }
        }
    }

    fun setMaxLines(value: Int) {
        synchronized(lock) {
            maxLines = value.coerceIn(50, 500)
            trimInMemory()
            persist()
        }
    }

    fun append(message: String) {
        if (message.isBlank()) return
        synchronized(lock) {
            val time = timeFormat.format(Date())
            lines.addLast("[$time] $message")
            trimInMemory()
            persist()
        }
    }

    fun recent(limit: Int = 200): String = synchronized(lock) {
        if (lines.isEmpty()) return@synchronized "（暂无日志）"
        val count = limit.coerceIn(1, lines.size)
        lines.toList().takeLast(count).joinToString("\n")
    }

    fun clear() {
        synchronized(lock) {
            lines.clear()
            persist()
        }
    }

    private fun trimInMemory() {
        while (lines.size > maxLines) {
            lines.removeFirst()
        }
    }

    private fun persist() {
        val file = logFile ?: return
        runCatching {
            file.writeText(lines.joinToString("\n"))
        }
    }
}
