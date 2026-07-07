package com.hascae.apkinstaller

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * 接收 PackageInstaller 的安裝 / 解除安裝狀態回呼。
 *  - STATUS_PENDING_USER_ACTION：開啟系統確認頁（失敗時退回通知）
 *  - 其餘最終狀態：轉送事件給 Flutter，並發出結果通知
 */
class InstallStatusReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE
        )
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val targetPackage = intent.getStringExtra("targetPackage")
            ?: intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME)
            ?: ""
        val appLabel = intent.getStringExtra("appLabel") ?: targetPackage
        val isUninstall = intent.action == InstallerEngine.ACTION_UNINSTALL_STATUS

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            EventBridge.send(
                mapOf(
                    "type" to "state",
                    "sessionId" to sessionId,
                    "phase" to "pending_user",
                    "package" to targetPackage
                )
            )
            if (confirm != null) {
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirm)
                } catch (_: Exception) {
                    // 背景啟動受限（例如使用者已離開應用）→ 改用通知讓使用者點擊確認
                    Notifications.notifyConfirm(context, confirm, sessionId)
                }
            }
            return
        }

        val success = status == PackageInstaller.STATUS_SUCCESS
        val friendly = if (success) "" else friendlyError(status, message)

        EventBridge.send(
            mapOf(
                "type" to "result",
                "kind" to if (isUninstall) "uninstall" else "install",
                "sessionId" to sessionId,
                "package" to targetPackage,
                "success" to success,
                "code" to status,
                "message" to friendly,
                "rawMessage" to (message ?: "")
            )
        )

        val title = when {
            isUninstall && success -> context.getString(R.string.notif_uninstall_success)
            isUninstall -> context.getString(R.string.notif_uninstall_failure)
            success -> context.getString(R.string.notif_install_success)
            else -> context.getString(R.string.notif_install_failure)
        }
        val text = if (success) appLabel else "$appLabel：$friendly"
        Notifications.notifyResult(
            context, title, text,
            if (sessionId != -1) sessionId else targetPackage.hashCode()
        )
    }

    /** 將系統狀態碼與原始訊息轉為繁體中文說明。 */
    private fun friendlyError(status: Int, raw: String?): String {
        val r = raw ?: ""
        return when {
            status == PackageInstaller.STATUS_FAILURE_ABORTED ->
                "已取消安裝（使用者拒絕或系統中止）"
            status == PackageInstaller.STATUS_FAILURE_BLOCKED ->
                "安裝遭到封鎖（可能由裝置政策或 Play 安全防護攔截）"
            status == PackageInstaller.STATUS_FAILURE_CONFLICT &&
                r.contains("INSTALL_FAILED_VERSION_DOWNGRADE") ->
                "無法降級安裝：欲安裝的版本低於已安裝版本，請先解除安裝舊版"
            status == PackageInstaller.STATUS_FAILURE_CONFLICT &&
                (r.contains("SIGNATURE") || r.contains("signatures")) ->
                "簽章衝突：安裝包簽章與已安裝版本不一致，請先解除安裝原版本"
            status == PackageInstaller.STATUS_FAILURE_CONFLICT ->
                "安裝衝突：$r"
            status == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE &&
                r.contains("INSTALL_FAILED_NO_MATCHING_ABIS") ->
                "架構不相容：安裝包不含此裝置 CPU 架構（ABI）的程式庫，請改選正確架構的分割包"
            status == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE &&
                r.contains("INSTALL_FAILED_OLDER_SDK") ->
                "系統版本過低：此應用要求的 Android 版本高於本機系統"
            status == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE ->
                "與此裝置不相容：$r"
            status == PackageInstaller.STATUS_FAILURE_INVALID &&
                r.contains("INSTALL_FAILED_MISSING_SPLIT") ->
                "缺少必要的分割包（split），請勾選完整的必要分割後重試"
            status == PackageInstaller.STATUS_FAILURE_INVALID ->
                "安裝包無效或已損毀：$r"
            status == PackageInstaller.STATUS_FAILURE_STORAGE ->
                "儲存空間不足或無法存取，請清理空間後重試"
            r.contains("INSTALL_FAILED_VERSION_DOWNGRADE") ->
                "無法降級安裝：欲安裝的版本低於已安裝版本，請先解除安裝舊版"
            r.isNotEmpty() -> r
            else -> "未知錯誤（狀態碼 $status）"
        }
    }
}
