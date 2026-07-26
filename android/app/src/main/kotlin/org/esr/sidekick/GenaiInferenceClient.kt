package org.esr.sidekick

import android.content.Context
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.generationConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Thin, Flutter-agnostic wrapper around the ML Kit GenAI Prompt API
 * (Gemini Nano via AICore, `com.google.mlkit:genai-prompt`).
 *
 * Shared by [OnDeviceAssistantBridge] (the Flutter chat screen's platform
 * channel) and [AiBenchReceiver] (the `tools/ai-bench.sh` battery/thermal
 * instrumentation hook) so both paths exercise the identical inference code.
 *
 * DESIGN CONSTRAINT: every call here is foreground / on-demand only.
 * Nothing in this file is registered with WorkManager or any background
 * scheduler (see `lib/src/background.dart` for the existing 15-min
 * calendar-poll job, which this must never touch). The [GenerativeModel]
 * handle is created lazily on first use and must be released via [close] by
 * the owner — nothing here keeps it resident once the caller is done.
 */
class GenaiInferenceClient(private val context: Context) {
    private var model: GenerativeModel? = null

    private fun client(): GenerativeModel =
        model ?: Generation.getClient(generationConfig {}).also { model = it }

    /**
     * Feature availability, mapped to plain ints so this same contract can
     * cross the Flutter platform channel unchanged:
     * 0=UNAVAILABLE 1=DOWNLOADABLE 2=DOWNLOADING 3=AVAILABLE.
     */
    suspend fun checkStatus(): Int =
        when (client().checkStatus()) {
            FeatureStatus.AVAILABLE -> 3
            FeatureStatus.DOWNLOADING -> 2
            FeatureStatus.DOWNLOADABLE -> 1
            else -> 0
        }

    /** Downloads the on-device model if needed; emits progress/terminal events. */
    fun download(): Flow<DownloadStatus> = client().download()

    /** Streams response text chunks as they're generated. */
    fun askStream(text: String): Flow<String> =
        client().generateContentStream(text).map { response ->
            response.candidates.firstOrNull()?.text ?: ""
        }

    /** Runs a single prompt to completion and returns the full text (used by ai-bench). */
    suspend fun askOnce(text: String): String {
        val response = client().generateContent(text)
        return response.candidates.firstOrNull()?.text ?: ""
    }

    /** Releases the native model handle. Safe to call more than once. */
    fun close() {
        model?.close()
        model = null
    }
}
