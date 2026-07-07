package com.hascae.apkinstaller

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.Process
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * 安裝引擎：以 PackageInstaller 工作階段（session）實作，
 * 完整支援單一 APK 與分割 APK（split APKs），涵蓋 Android 7（API 24）～ Android 16（API 36）。
 */
object InstallerEngine {

    const val ACTION_INSTALL_STATUS = "com.hascae.apkinstaller.INSTALL_STATUS"
    const val ACTION_UNINSTALL_STATUS = "com.hascae.apkinstaller.UNINSTALL_STATUS"

    /**
     * 建立工作階段並串流寫入所選 APK。
     * @param path       安裝包本機路徑
     * @param entries    分割包容器中要安裝的 zip entry 名稱；單一 APK 時傳 null
     * @param packageName 目標套件名稱（用於事件與通知）
     * @param appLabel   應用顯示名稱
     * @param allowUserActionSkip 更新且本應用為安裝來源時，嘗試免確認更新（Android 12+）
     * @param requestUpdateOwnership Android 14+ 請求更新擁有權
     */
    fun install(
        context: Context,
        path: String,
        entries: List<String>?,
        packageName: String,
        appLabel: String,
        allowUserActionSkip: Boolean,
        requestUpdateOwnership: Boolean
    ): Int {
        val file = File(path)
        if (!file.exists()) throw IllegalStateException("找不到檔案：$path")

        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        )
        params.setAppPackageName(packageName)
        params.setOriginatingUid(Process.myUid())
        if (Build.VERSION.SDK_INT >= 26) {
            params.setInstallReason(PackageManager.INSTALL_REASON_USER)
        }
        if (Build.VERSION.SDK_INT >= 31) {
            params.setRequireUserAction(
                if (allowUserActionSkip) {
                    PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED
                } else {
                    PackageInstaller.SessionParams.USER_ACTION_REQUIRED
                }
            )
        }
        if (Build.VERSION.SDK_INT >= 34 && requestUpdateOwnership) {
            params.setRequestUpdateOwnership(true)
        }

        // 預估總大小，讓系統預留空間
        val totalSize: Long = if (entries == null) {
            file.length()
        } else {
            ZipFile(file).use { zip ->
                entries.sumOf { name -> zip.getEntry(name)?.size?.coerceAtLeast(0L) ?: 0L }
            }
        }
        if (totalSize > 0) params.setSize(totalSize)

        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            if (entries == null) {
                FileInputStream(file).use { ins ->
                    writeToSession(session, "base.apk", ins, file.length(), totalSize, 0L, sessionId)
                }
            } else {
                ZipFile(file).use { zip ->
                    var written = 0L
                    val usedNames = HashSet<String>()
                    for (entryName in entries) {
                        val entry: ZipEntry = zip.getEntry(entryName)
                            ?: throw IllegalStateException("壓縮檔中找不到：$entryName")
                        var streamName = entryName.substringAfterLast('/')
                            .replace(Regex("[^A-Za-z0-9._-]"), "_")
                        while (!usedNames.add(streamName)) {
                            streamName = "_$streamName"
                        }
                        zip.getInputStream(entry).use { ins ->
                            writeToSession(
                                session, streamName, ins, entry.size, totalSize, written, sessionId
                            )
                        }
                        written += entry.size.coerceAtLeast(0L)
                    }
                }
            }

            EventBridge.send(
                mapOf(
                    "type" to "state", "sessionId" to sessionId,
                    "phase" to "committing", "package" to packageName
                )
            )

            val intent = Intent(context, InstallStatusReceiver::class.java)
                .setAction(ACTION_INSTALL_STATUS)
                .setPackage(context.packageName)
                .putExtra("targetPackage", packageName)
                .putExtra("appLabel", appLabel)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pi = PendingIntent.getBroadcast(context, sessionId, intent, flags)
            session.commit(pi.intentSender)
        } catch (e: Exception) {
            try {
                session.abandon()
            } catch (_: Exception) {
            }
            throw e
        } finally {
            session.close()
        }
        return sessionId
    }

    private fun writeToSession(
        session: PackageInstaller.Session,
        name: String,
        input: InputStream,
        lengthHint: Long,
        totalSize: Long,
        alreadyWritten: Long,
        sessionId: Int
    ) {
        session.openWrite(name, 0, lengthHint.coerceAtLeast(-1L)).use { os ->
            val buf = ByteArray(512 * 1024)
            var done = 0L
            var lastReport = 0L
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                os.write(buf, 0, n)
                done += n
                if (done - lastReport > 1024 * 1024) {
                    lastReport = done
                    EventBridge.send(
                        mapOf(
                            "type" to "copy",
                            "sessionId" to sessionId,
                            "entry" to name,
                            "done" to (alreadyWritten + done),
                            "total" to totalSize
                        )
                    )
                }
            }
            session.fsync(os)
        }
    }

    // ---------- 解除安裝 ----------

    fun uninstall(context: Context, packageName: String, appLabel: String) {
        val installer = context.packageManager.packageInstaller
        val intent = Intent(context, InstallStatusReceiver::class.java)
            .setAction(ACTION_UNINSTALL_STATUS)
            .setPackage(context.packageName)
            .putExtra("targetPackage", packageName)
            .putExtra("appLabel", appLabel)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        val pi = PendingIntent.getBroadcast(
            context, packageName.hashCode(), intent, flags
        )
        installer.uninstall(packageName, pi.intentSender)
    }

    // ---------- OBB 資源檔 ----------

    /**
     * 將 XAPK 內的 OBB 檔複製到 Android/obb/<package>/。
     * 各版本行為不同：API ≤ 29 需寫入權限；API 30+ 需「所有檔案存取」，
     * 且部分新版系統（13+）可能完全禁止第三方寫入 obb 目錄 —— 失敗時回傳明確訊息。
     */
    fun installObb(
        context: Context,
        path: String,
        entries: List<String>,
        packageName: String
    ): Map<String, Any?> {
        val file = File(path)
        @Suppress("DEPRECATION")
        val obbRoot = File(Environment.getExternalStorageDirectory(), "Android/obb/$packageName")
        try {
            if (!obbRoot.exists() && !obbRoot.mkdirs()) {
                return mapOf(
                    "ok" to false,
                    "message" to "無法建立 OBB 目錄（此 Android 版本可能限制存取 Android/obb）"
                )
            }
            ZipFile(file).use { zip ->
                var total = 0L
                var done = 0L
                for (name in entries) {
                    total += zip.getEntry(name)?.size?.coerceAtLeast(0L) ?: 0L
                }
                for (name in entries) {
                    val entry = zip.getEntry(name) ?: continue
                    val target = File(obbRoot, name.substringAfterLast('/'))
                    zip.getInputStream(entry).use { ins ->
                        FileOutputStream(target).use { os ->
                            val buf = ByteArray(512 * 1024)
                            var lastReport = 0L
                            while (true) {
                                val n = ins.read(buf)
                                if (n < 0) break
                                os.write(buf, 0, n)
                                done += n
                                if (done - lastReport > 2 * 1024 * 1024) {
                                    lastReport = done
                                    EventBridge.send(
                                        mapOf("type" to "obb", "done" to done, "total" to total)
                                    )
                                }
                            }
                            os.fd.sync()
                        }
                    }
                }
            }
            return mapOf("ok" to true, "message" to "")
        } catch (e: Exception) {
            return mapOf(
                "ok" to false,
                "message" to "OBB 複製失敗：${e.message ?: e.javaClass.simpleName}"
            )
        }
    }

    // ---------- 匯出已安裝應用 ----------

    /**
     * 匯出已安裝應用的 APK。無分割包時輸出單一 .apk；
     * 有分割包時打包為 .apks（可用本應用重新安裝）。
     * 輸出至快取目錄，由 Flutter 端以分享方式讓使用者另存。
     */
    fun exportApp(context: Context, packageName: String): Map<String, Any?> {
        val pm = context.packageManager
        val ai = if (Build.VERSION.SDK_INT >= 33) {
            pm.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getApplicationInfo(packageName, 0)
        }
        val label = ai.loadLabel(pm).toString()
            .replace(Regex("[\\\\/:*?\"<>|\\s]+"), "_")
        val pkgInfo = if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(packageName, 0)
        }
        val version = pkgInfo.versionName ?: "0"

        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val splitDirs = ai.splitSourceDirs
        val base = File(ai.sourceDir)

        return if (splitDirs.isNullOrEmpty()) {
            val out = File(dir, "${label}_$version.apk")
            base.inputStream().use { ins ->
                FileOutputStream(out).use { os -> ins.copyTo(os, 512 * 1024) }
            }
            mapOf("path" to out.absolutePath, "name" to out.name, "size" to out.length())
        } else {
            val out = File(dir, "${label}_$version.apks")
            ZipOutputStream(FileOutputStream(out)).use { zos ->
                zipAdd(zos, base, "base.apk")
                for (split in splitDirs) {
                    val f = File(split)
                    zipAdd(zos, f, f.name)
                }
            }
            mapOf("path" to out.absolutePath, "name" to out.name, "size" to out.length())
        }
    }

    private fun zipAdd(zos: ZipOutputStream, file: File, name: String) {
        zos.putNextEntry(ZipEntry(name))
        file.inputStream().use { ins -> ins.copyTo(zos as OutputStream, 512 * 1024) }
        zos.closeEntry()
    }

    /** 清除匯入 / 分析 / 匯出快取，回傳釋放的位元組數。 */
    fun clearCache(context: Context): Long {
        var freed = 0L
        for (sub in listOf("imports", "analysis", "exports")) {
            val dir = File(context.cacheDir, sub)
            if (dir.exists()) {
                dir.walkBottomUp().forEach { f ->
                    if (f.isFile) freed += f.length()
                    f.delete()
                }
            }
        }
        return freed
    }

    /** 依副檔名猜測檔案是否為本安裝器支援的類型。 */
    fun isSupportedFileName(name: String): Boolean {
        val n = name.lowercase(Locale.ROOT)
        return n.endsWith(".apk") || n.endsWith(".apkm") || n.endsWith(".xapk") ||
            n.endsWith(".apks") || n.endsWith(".zip")
    }
}
