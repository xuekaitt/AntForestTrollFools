package com.antmanor.automation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

object StatusNotifier {

    const val CHANNEL_ID = "manor_status"
    const val EXTRA_TEXT = "status_text"
    const val NOTIFICATION_ID = 1001

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        )
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    fun build(context: Context, text: String): Notification {
        ensureChannel(context)
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_manor)
            .setContentTitle(context.getString(R.string.notification_title))
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
    }

    fun startOrUpdate(context: Context, text: String) {
        val intent = Intent(context, StatusForegroundService::class.java).putExtra(EXTRA_TEXT, text)
        runCatching {
            context.startForegroundService(intent)
        }.onFailure {
            LogStore.append("前台服务启动失败（${it.javaClass.simpleName}），改为普通通知")
            postPlain(context, text)
        }
    }

    fun stop(context: Context) {
        runCatching {
            context.stopService(Intent(context, StatusForegroundService::class.java))
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.cancel(NOTIFICATION_ID)
    }

    private fun postPlain(context: Context, text: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        runCatching {
            manager.notify(NOTIFICATION_ID, build(context, text))
        }
    }
}

class StatusForegroundService : Service() {

    override fun onCreate() {
        super.onCreate()
        StatusNotifier.ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(StatusNotifier.EXTRA_TEXT) ?: "运行中"
        startForeground(StatusNotifier.NOTIFICATION_ID, StatusNotifier.build(this, text))
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
