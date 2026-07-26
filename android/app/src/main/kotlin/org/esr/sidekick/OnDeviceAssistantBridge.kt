package org.esr.sidekick

import android.content.Context
import com.google.mlkit.genai.common.DownloadStatus
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Flutter platform-channel boundary for the Pulse "on-device AI" chat screen
 * (`lib/src/on_device_chat_screen.dart` / `lib/src/on_device_assistant.dart`).
 *
 * Wraps [GenaiInferenceClient] — see that file for the design-constraint
 * rationale (foreground/on-demand only) and `on_device_assistant.dart` for
 * why this is a hand-rolled channel instead of the `google_mlkit_genai_prompt`
 * pub.dev plugin (its native `runInference` is a hardcoded stub as of the
 * currently published 0.2.0 / develop branch — verified 2026-07-26).
 *
 * Method channel `org.esr.sidekick/on_device_assistant`:
 *   - `checkStatus` -> Int (0=unavailable 1=downloadable 2=downloading 3=available)
 *   - `downloadModel` -> Unit; progress streams on the download event channel
 *   - `ask({text: String})` -> Unit; chunks stream on the stream event channel
 *   - `cancelAsk` -> Unit
 *   - `close` -> Unit
 *
 * Event channels:
 *   - `org.esr.sidekick/on_device_assistant/stream` — {event: chunk|done|error, text?, error?}
 *   - `org.esr.sidekick/on_device_assistant/download` — {event: started|progress|completed|failed, bytes?, error?}
 */
class OnDeviceAssistantBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val METHOD_CHANNEL = "org.esr.sidekick/on_device_assistant"
        const val STREAM_CHANNEL = "org.esr.sidekick/on_device_assistant/stream"
        const val DOWNLOAD_CHANNEL = "org.esr.sidekick/on_device_assistant/download"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val inference = GenaiInferenceClient(context.applicationContext)
    private var streamSink: EventChannel.EventSink? = null
    private var downloadSink: EventChannel.EventSink? = null
    private var askJob: Job? = null
    private var downloadJob: Job? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, STREAM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    streamSink = events
                }

                override fun onCancel(arguments: Any?) {
                    streamSink = null
                }
            },
        )
        EventChannel(messenger, DOWNLOAD_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    downloadSink = events
                }

                override fun onCancel(arguments: Any?) {
                    downloadSink = null
                }
            },
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkStatus" -> checkStatus(result)
            "downloadModel" -> downloadModel(result)
            "ask" -> ask(call.argument<String>("text") ?: "", result)
            "cancelAsk" -> {
                askJob?.cancel()
                result.success(null)
            }
            "close" -> {
                closeModel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun checkStatus(result: MethodChannel.Result) {
        scope.launch {
            try {
                result.success(inference.checkStatus())
            } catch (e: Throwable) {
                // Catches Throwable, not just Exception: a missing AICore /
                // Play services module can surface as a NoClassDefFoundError
                // (an Error, not an Exception). Any failure here means
                // "unavailable" to the Dart side, never an app crash.
                result.error("GENAI_UNAVAILABLE", e.message, null)
            }
        }
    }

    private fun downloadModel(result: MethodChannel.Result) {
        downloadJob?.cancel()
        downloadJob = scope.launch {
            try {
                inference.download().collect { status ->
                    downloadSink?.success(downloadStatusToMap(status))
                }
                result.success(null)
            } catch (e: Throwable) {
                downloadSink?.success(mapOf("event" to "failed", "error" to e.toString()))
                result.error("DOWNLOAD_FAILED", e.message, null)
            }
        }
    }

    private fun downloadStatusToMap(status: DownloadStatus): Map<String, Any?> =
        when (status) {
            is DownloadStatus.DownloadStarted ->
                mapOf("event" to "started", "bytes" to status.bytesToDownload)
            is DownloadStatus.DownloadProgress ->
                mapOf("event" to "progress", "bytes" to status.totalBytesDownloaded)
            is DownloadStatus.DownloadFailed ->
                mapOf("event" to "failed", "error" to status.e.toString())
            is DownloadStatus.DownloadCompleted -> mapOf("event" to "completed")
            else -> mapOf("event" to "progress")
        }

    private fun ask(text: String, result: MethodChannel.Result) {
        if (text.isBlank()) {
            result.error("EMPTY_PROMPT", "Prompt text is empty", null)
            return
        }
        askJob?.cancel()
        askJob = scope.launch {
            try {
                inference.askStream(text).collect { chunk ->
                    if (chunk.isNotEmpty()) {
                        streamSink?.success(mapOf("event" to "chunk", "text" to chunk))
                    }
                }
                streamSink?.success(mapOf("event" to "done"))
                result.success(null)
            } catch (e: Throwable) {
                streamSink?.success(mapOf("event" to "error", "error" to e.toString()))
                result.error("INFERENCE_FAILED", e.message, null)
            }
        }
    }

    private fun closeModel() {
        askJob?.cancel()
        downloadJob?.cancel()
        inference.close()
    }

    fun dispose() {
        closeModel()
        scope.cancel()
    }
}
