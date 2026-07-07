package com.hascae.apkinstaller

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "apkinstaller/methods"
        private const val EVENT_CHANNEL = "apkinstaller/events"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 由檔案管理器 / 分享開啟時暫存的 URI，待 Flutter 端取走。 */
    private var pendingUri: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        handleIntent(intent, coldStart = true)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(EventBridge)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceInfo" -> result.success(deviceInfo())
                    "getPermissionState" -> result.success(permissionState())
                    "requestInstallPermission" -> {
                        requestInstallPermission(); result.success(null)
                    }
                    "requestAllFilesPermission" -> {
                        requestAllFilesPermission(); result.success(null)
                    }
                    "takePendingFile" -> {
                        val uri = pendingUri
                        pendingUri = null
                        result.success(uri)
                    }
                    "importUri" -> runAsync(result) {
                        ArchiveAnalyzer.importUri(this, call.argument<String>("uri")!!)
                    }
                    "analyze" -> runAsync(result) {
                        ArchiveAnalyzer.analyze(this, call.argument<String>("path")!!)
                    }
                    "install" -> runAsync(result) {
                        val id = InstallerEngine.install(
                            this,
                            call.argument<String>("path")!!,
                            call.argument<List<String>>("entries"),
                            call.argument<String>("packageName") ?: "",
                            call.argument<String>("appLabel") ?: "",
                            call.argument<Boolean>("allowUserActionSkip") ?: false,
                            call.argument<Boolean>("requestUpdateOwnership") ?: false
                        )
                        mapOf("sessionId" to id)
                    }
                    "installObb" -> runAsync(result) {
                        InstallerEngine.installObb(
                            this,
                            call.argument<String>("path")!!,
                            call.argument<List<String>>("entries")!!,
                            call.argument<String>("packageName")!!
                        )
                    }
                    "uninstall" -> runAsync(result) {
                        InstallerEngine.uninstall(
                            this,
                            call.argument<String>("packageName")!!,
                            call.argument<String>("appLabel") ?: ""
                        )
                        null
                    }
                    "listApps" -> runAsync(result) {
                        AppRepository.listApps(
                            this, call.argument<Boolean>("includeSystem") ?: false
                        )
                    }
                    "getAppIcon" -> runAsync(result) {
                        AppRepository.getAppIcon(
                            this,
                            call.argument<String>("packageName")!!,
                            call.argument<Int>("sizePx") ?: 96
                        )
                    }
                    "exportApp" -> runAsync(result) {
                        InstallerEngine.exportApp(this, call.argument<String>("packageName")!!)
                    }
                    "openApp" -> result.success(
                        AppRepository.openApp(this, call.argument<String>("packageName")!!)
                    )
                    "openAppSettings" -> {
                        AppRepository.openSystemAppSettings(
                            this, call.argument<String>("packageName")!!
                        )
                        result.success(null)
                    }
                    "clearCache" -> runAsync(result) { InstallerEngine.clearCache(this) }
                    else -> result.notImplemented()
                }
            }
    }

    /** 在背景執行緒執行耗時工作，完成後切回主執行緒回覆。 */
    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("native_error", e.message ?: e.javaClass.simpleName, null)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, coldStart = false)
    }

    /** 處理「以此應用開啟安裝包」與「分享到此應用」。 */
    private fun handleIntent(intent: Intent?, coldStart: Boolean) {
        intent ?: return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            }
            else -> null
        } ?: return
        // 嘗試取得長期讀取授權（部分來源不允許，忽略失敗）
        try {
            grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
        }
        pendingUri = uri.toString()
        if (!coldStart) {
            EventBridge.send(mapOf("type" to "new_file", "uri" to uri.toString()))
        }
    }

    // ---------- 權限 ----------

    private fun deviceInfo(): Map<String, Any?> = mapOf(
        "sdkInt" to Build.VERSION.SDK_INT,
        "release" to Build.VERSION.RELEASE,
        "model" to Build.MODEL,
        "brand" to Build.BRAND,
        "abis" to Build.SUPPORTED_ABIS.toList(),
        "densityDpi" to resources.displayMetrics.densityDpi,
        "locales" to currentLocales()
    )

    private fun currentLocales(): List<String> {
        val list = ArrayList<String>()
        val locales = resources.configuration.locales
        for (i in 0 until locales.size()) {
            list.add(locales.get(i).toLanguageTag())
        }
        return list
    }

    /**
     * 安裝權限狀態：
     *  - API 26+：canRequestPackageInstalls()
     *  - API 24/25：讀取「未知來源」系統設定
     */
    private fun permissionState(): Map<String, Any?> {
        val canInstall = if (Build.VERSION.SDK_INT >= 26) {
            packageManager.canRequestPackageInstalls()
        } else {
            try {
                // API 17 起此設定移至 Settings.Global；Secure 作為舊機型後備
                @Suppress("DEPRECATION")
                (Settings.Global.getInt(
                    contentResolver, Settings.Global.INSTALL_NON_MARKET_APPS, -1
                ).takeIf { it >= 0 }
                    ?: Settings.Secure.getInt(
                        contentResolver, Settings.Secure.INSTALL_NON_MARKET_APPS, 0
                    )) == 1
            } catch (_: Exception) {
                true
            }
        }
        val allFiles = if (Build.VERSION.SDK_INT >= 30) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
        val legacyStorage = if (Build.VERSION.SDK_INT in 24..29) {
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT in 30..32) {
            checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val notifications = if (Build.VERSION.SDK_INT >= 33) {
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        return mapOf(
            "canInstall" to canInstall,
            "allFiles" to allFiles,
            "legacyStorage" to legacyStorage,
            "notifications" to notifications,
            "sdkInt" to Build.VERSION.SDK_INT
        )
    }

    private fun requestInstallPermission() {
        if (Build.VERSION.SDK_INT >= 26) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            try {
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            }
        } else {
            // Android 7.x：前往「安全性」設定開啟未知來源
            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }
    }

    private fun requestAllFilesPermission() {
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
    }
}
