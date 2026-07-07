package com.hascae.apkinstaller

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * 將原生事件（複製進度、安裝狀態、安裝結果、外部開檔）以單一 EventChannel
 * 送往 Flutter。所有事件一律切回主執行緒發送。
 */
object EventBridge : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var sink: EventChannel.EventSink? = null

    /** Flutter 尚未連線時暫存的事件（例如：由檔案管理器冷啟動時的結果廣播）。 */
    private val pending = ArrayDeque<Map<String, Any?>>()

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        mainHandler.post {
            while (pending.isNotEmpty() && sink != null) {
                sink?.success(pending.removeFirst())
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun send(event: Map<String, Any?>) {
        mainHandler.post {
            val s = sink
            if (s != null) {
                s.success(event)
            } else {
                pending.addLast(event)
                // 避免無限成長
                while (pending.size > 64) pending.removeFirst()
            }
        }
    }
}
