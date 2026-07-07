package com.hascae.apkinstaller

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * 安裝 / 解除安裝結果通知。
 * Android 8.0+ 使用通知頻道；Android 13+ 需 POST_NOTIFICATIONS 權限（由 Flutter 端申請）。
 */
object Notifications {
    private const val CHANNEL_ID = "install_results"

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.notif_channel_install),
                    NotificationManager.IMPORTANCE_DEFAULT
                )
                ch.description = context.getString(R.string.notif_channel_install_desc)
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            return context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    fun notifyResult(context: Context, title: String, text: String, id: Int) {
        if (!canNotify(context)) return
        ensureChannel(context)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, 0, it, flags)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_DEFAULT)
        }
        builder.setSmallIcon(R.drawable.ic_stat_install)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
        if (contentIntent != null) builder.setContentIntent(contentIntent)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, builder.build())
    }

    /** 需要使用者確認安裝、但無法直接開啟確認頁時的備援通知。 */
    fun notifyConfirm(context: Context, confirmIntent: Intent, id: Int) {
        if (!canNotify(context)) return
        ensureChannel(context)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        val pi = PendingIntent.getActivity(context, id, confirmIntent, flags)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        builder.setSmallIcon(R.drawable.ic_stat_install)
            .setContentTitle("需要確認安裝")
            .setContentText("點選以繼續完成安裝")
            .setContentIntent(pi)
            .setAutoCancel(true)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, builder.build())
    }
}
