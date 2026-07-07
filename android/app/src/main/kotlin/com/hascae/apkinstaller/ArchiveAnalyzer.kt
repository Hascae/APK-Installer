package com.hascae.apkinstaller

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipFile

/**
 * 安裝包解析器：
 *  - 將 content:// 匯入應用快取（串流複製、回報進度）
 *  - 判斷檔案型別（單一 APK 或 APKM / XAPK / APKS / ZIP 分割包）
 *  - 解析套件資訊（名稱、圖示、版本、minSdk/targetSdk、簽章）
 *  - 列出分割包（依 ABI / 螢幕密度 / 語言 / 動態功能 分類）與 OBB 資源檔
 */
object ArchiveAnalyzer {

    private val ABI_TOKENS = setOf(
        "armeabi", "armeabi_v7a", "arm64_v8a", "x86", "x86_64", "mips", "mips64"
    )
    private val DPI_TOKENS = setOf(
        "ldpi", "mdpi", "tvdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi", "nodpi"
    )

    // ---------- 匯入 ----------

    /** 將任意 URI（content:// 或 file://）匯入快取目錄，回傳本機檔案。 */
    fun importUri(context: Context, uriString: String): Map<String, Any?> {
        val uri = Uri.parse(uriString)
        if (uri.scheme == "file" || uri.scheme == null) {
            val f = File(uri.path ?: uriString)
            if (!f.canRead()) throw IllegalStateException("無法讀取檔案：${f.path}")
            return mapOf("path" to f.absolutePath, "name" to f.name, "size" to f.length())
        }

        val resolver = context.contentResolver
        var name = "package.apk"
        var total = -1L
        resolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val si = c.getColumnIndex(OpenableColumns.SIZE)
                if (ni >= 0) c.getString(ni)?.let { name = it }
                if (si >= 0 && !c.isNull(si)) total = c.getLong(si)
            }
        }
        val dir = File(context.cacheDir, "imports").apply { mkdirs() }
        val out = File(dir, sanitizeFileName(name))
        val input: InputStream = resolver.openInputStream(uri)
            ?: throw IllegalStateException("無法開啟資料串流")
        input.use { ins ->
            FileOutputStream(out).use { os ->
                val buf = ByteArray(256 * 1024)
                var done = 0L
                var lastReport = 0L
                while (true) {
                    val n = ins.read(buf)
                    if (n < 0) break
                    os.write(buf, 0, n)
                    done += n
                    if (done - lastReport > 1024 * 1024) {
                        lastReport = done
                        EventBridge.send(
                            mapOf("type" to "import", "done" to done, "total" to total)
                        )
                    }
                }
                os.fd.sync()
            }
        }
        return mapOf("path" to out.absolutePath, "name" to name, "size" to out.length())
    }

    private fun sanitizeFileName(name: String): String =
        name.replace(Regex("[\\\\/:*?\"<>|]"), "_")

    // ---------- 解析 ----------

    fun analyze(context: Context, path: String): Map<String, Any?> {
        val file = File(path)
        if (!file.exists()) throw IllegalStateException("找不到檔案：$path")

        val isSingleApk = isPlainApk(file)
        return if (isSingleApk) analyzeSingleApk(context, file) else analyzeBundle(context, file)
    }

    /** 檔案根目錄含 AndroidManifest.xml 即視為單一 APK；否則視為分割包容器。 */
    private fun isPlainApk(file: File): Boolean {
        return try {
            ZipFile(file).use { zip ->
                zip.getEntry("AndroidManifest.xml") != null && zip.getEntry("classes.dex") != null
            }
        } catch (_: Exception) {
            // 連 zip 都開不了，讓後續流程丟出更明確的錯誤
            file.name.lowercase(Locale.ROOT).endsWith(".apk")
        }
    }

    private fun analyzeSingleApk(context: Context, file: File): Map<String, Any?> {
        val meta = readApkMeta(context, file)
            ?: throw IllegalStateException("無法解析 APK（檔案可能已損毀）")
        val result = HashMap<String, Any?>(meta)
        result["kind"] = "apk"
        result["path"] = file.absolutePath
        result["fileName"] = file.name
        result["fileSize"] = file.length()
        result["splits"] = emptyList<Map<String, Any?>>()
        result["obbs"] = emptyList<Map<String, Any?>>()
        attachInstalledInfo(context, result)
        return result
    }

    private fun analyzeBundle(context: Context, file: File): Map<String, Any?> {
        val splits = ArrayList<Map<String, Any?>>()
        val obbs = ArrayList<Map<String, Any?>>()
        var baseEntry: String? = null
        var largestApk: String? = null
        var largestSize = -1L

        ZipFile(file).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val e = entries.nextElement()
                if (e.isDirectory) continue
                val entryName = e.name
                val lower = entryName.lowercase(Locale.ROOT)
                val base = entryName.substringAfterLast('/')
                when {
                    lower.endsWith(".apk") -> {
                        val cls = classifySplit(base)
                        splits.add(
                            mapOf(
                                "entry" to entryName,
                                "name" to base,
                                "size" to e.size,
                                "kind" to cls.first,
                                "tag" to cls.second
                            )
                        )
                        if (cls.first == "base" && baseEntry == null) baseEntry = entryName
                        if (cls.first != "abi" && cls.first != "dpi" && cls.first != "lang" &&
                            e.size > largestSize
                        ) {
                            largestSize = e.size
                            largestApk = entryName
                        }
                    }
                    lower.endsWith(".obb") -> {
                        obbs.add(mapOf("entry" to entryName, "name" to base, "size" to e.size))
                    }
                }
            }
        }

        if (splits.isEmpty()) {
            throw IllegalStateException("這個壓縮檔內沒有任何 APK，無法安裝")
        }
        val resolvedBase = baseEntry ?: largestApk ?: (splits.first()["entry"] as String)

        // 將 base.apk 抽出到快取以解析套件資訊
        val tmpDir = File(context.cacheDir, "analysis").apply { mkdirs() }
        val tmpBase = File(tmpDir, "base_${file.name.hashCode()}.apk")
        ZipFile(file).use { zip ->
            val entry = zip.getEntry(resolvedBase)
                ?: throw IllegalStateException("讀取分割包失敗")
            zip.getInputStream(entry).use { ins ->
                FileOutputStream(tmpBase).use { os -> ins.copyTo(os, 256 * 1024) }
            }
        }

        val meta = readApkMeta(context, tmpBase)
            ?: throw IllegalStateException("無法解析主要 APK（base.apk）")

        // 修正 splits 中 base 的判定（確保與 resolvedBase 一致）
        val fixedSplits = splits.map {
            if (it["entry"] == resolvedBase && it["kind"] != "base") {
                val m = HashMap(it); m["kind"] = "base"; m["tag"] = ""; m
            } else it
        }

        val result = HashMap<String, Any?>(meta)
        result["kind"] = "bundle"
        result["path"] = file.absolutePath
        result["fileName"] = file.name
        result["fileSize"] = file.length()
        result["baseEntry"] = resolvedBase
        result["splits"] = fixedSplits
        result["obbs"] = obbs
        attachInstalledInfo(context, result)
        tmpBase.delete()
        return result
    }

    /**
     * 依檔名將分割 APK 分類。
     * 支援 APKMirror（split_config.*）、SAI / APKPure（config.*）、
     * bundletool（base-master / base-arm64_v8a 等）與動態功能模組。
     */
    private fun classifySplit(fileName: String): Pair<String, String> {
        val n = fileName.lowercase(Locale.ROOT).removeSuffix(".apk")
        if (n == "base" || n == "base-master" || n == "base-master_2") return "base" to ""

        // config 後綴：config.arm64_v8a / split_config.zh / com.foo.config.xxhdpi
        val configIdx = n.lastIndexOf("config.")
        var token: String? = null
        if (configIdx >= 0) {
            token = n.substring(configIdx + "config.".length)
        } else if (n.startsWith("base-")) {
            token = n.removePrefix("base-")
        }
        if (token != null) {
            val t = token.replace('-', '_')
            return when {
                ABI_TOKENS.contains(t) -> "abi" to t
                DPI_TOKENS.contains(t) -> "dpi" to t
                t.length in 2..3 || t.matches(Regex("[a-z]{2}_[a-z]{2}")) -> "lang" to t
                else -> "other" to t
            }
        }
        // 其他：動態功能模組（split_<feature>.apk 或任意名稱）
        val feature = n.removePrefix("split_")
        return "feature" to feature
    }

    /** 讀取 APK 的套件資訊（名稱 / 圖示 / 版本 / SDK / 簽章）。 */
    private fun readApkMeta(context: Context, apkFile: File): Map<String, Any?>? {
        val pm = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        val info: PackageInfo = pm.getPackageArchiveInfo(apkFile.absolutePath, flags) ?: return null
        val ai = info.applicationInfo
        var label: String? = null
        var iconBytes: ByteArray? = null
        if (ai != null) {
            ai.sourceDir = apkFile.absolutePath
            ai.publicSourceDir = apkFile.absolutePath
            label = try {
                ai.loadLabel(pm).toString()
            } catch (_: Exception) {
                null
            }
            iconBytes = try {
                drawableToPng(ai.loadIcon(pm), 192)
            } catch (_: Exception) {
                null
            }
        }
        val versionCode = if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "packageName" to info.packageName,
            "label" to (label ?: info.packageName),
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCode,
            "minSdk" to (ai?.minSdkVersion ?: 0),
            "targetSdk" to (ai?.targetSdkVersion ?: 0),
            "iconBytes" to iconBytes,
            "archiveSignature" to signatureSha256(info)
        )
    }

    /** 附上目前已安裝版本的比較資訊。 */
    private fun attachInstalledInfo(context: Context, result: HashMap<String, Any?>) {
        val pkg = result["packageName"] as? String ?: return
        val pm = context.packageManager
        val installed: PackageInfo? = try {
            val flags = if (Build.VERSION.SDK_INT >= 28) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }
            if (Build.VERSION.SDK_INT >= 33) {
                pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(flags.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, flags)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
        if (installed == null) {
            result["installed"] = null
            return
        }
        val vc = if (Build.VERSION.SDK_INT >= 28) {
            installed.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            installed.versionCode.toLong()
        }
        val installedSig = signatureSha256(installed)
        val archiveSig = result["archiveSignature"] as? String
        val match: Boolean? =
            if (installedSig != null && archiveSig != null) installedSig == archiveSig else null
        result["installed"] = mapOf(
            "versionName" to (installed.versionName ?: ""),
            "versionCode" to vc,
            "signatureMatch" to match,
            "isSelf" to (pkg == context.packageName)
        )
    }

    private fun signatureSha256(info: PackageInfo): String? {
        return try {
            val sig = if (Build.VERSION.SDK_INT >= 28) {
                val signingInfo = info.signingInfo ?: return null
                val signers = if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
                signers?.firstOrNull() ?: return null
            } else {
                @Suppress("DEPRECATION")
                info.signatures?.firstOrNull() ?: return null
            }
            val md = MessageDigest.getInstance("SHA-256")
            md.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            null
        }
    }

    fun drawableToPng(drawable: Drawable, sizePx: Int): ByteArray {
        val bmp: Bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, sizePx, sizePx, true)
        } else {
            val b = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val c = Canvas(b)
            drawable.setBounds(0, 0, sizePx, sizePx)
            drawable.draw(c)
            b
        }
        val bos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
        return bos.toByteArray()
    }
}
