package com.hascae.apkinstaller

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File

/**
 * 已安裝應用清單（供「應用管理」頁使用）。
 * 圖示採延遲載入（getAppIcon），避免一次傳輸過大的資料。
 */
object AppRepository {

    fun listApps(context: Context, includeSystem: Boolean): List<Map<String, Any?>> {
        val pm = context.packageManager
        val packages = if (Build.VERSION.SDK_INT >= 33) {
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(0)
        }
        val out = ArrayList<Map<String, Any?>>(packages.size)
        for (info in packages) {
            val ai = info.applicationInfo ?: continue
            val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val isUpdatedSystem = (ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            if (!includeSystem && isSystem && !isUpdatedSystem) continue

            val versionCode = if (Build.VERSION.SDK_INT >= 28) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            var apkSize = try {
                File(ai.sourceDir).length()
            } catch (_: Exception) {
                0L
            }
            val splitCount = ai.splitSourceDirs?.size ?: 0
            ai.splitSourceDirs?.forEach { s ->
                apkSize += try {
                    File(s).length()
                } catch (_: Exception) {
                    0L
                }
            }
            out.add(
                mapOf(
                    "package" to info.packageName,
                    "label" to (ai.loadLabel(pm)?.toString() ?: info.packageName),
                    "versionName" to (info.versionName ?: ""),
                    "versionCode" to versionCode,
                    "system" to isSystem,
                    "splits" to splitCount,
                    "apkSize" to apkSize,
                    "firstInstall" to info.firstInstallTime,
                    "lastUpdate" to info.lastUpdateTime,
                    "enabled" to ai.enabled
                )
            )
        }
        out.sortBy { (it["label"] as String).lowercase() }
        return out
    }

    fun getAppIcon(context: Context, packageName: String, sizePx: Int): ByteArray? {
        return try {
            val pm = context.packageManager
            val icon = pm.getApplicationIcon(packageName)
            ArchiveAnalyzer.drawableToPng(icon, sizePx)
        } catch (_: Exception) {
            null
        }
    }

    fun openApp(context: Context, packageName: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun openSystemAppSettings(context: Context, packageName: String) {
        val intent = android.content.Intent(
            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            android.net.Uri.parse("package:$packageName")
        )
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
