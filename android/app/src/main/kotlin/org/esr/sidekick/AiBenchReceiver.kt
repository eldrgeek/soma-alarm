package org.esr.sidekick

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Instrumentation hook for `tools/ai-bench.sh` — NOT part of normal app
 * usage. Drives a scripted loop of on-device prompts directly through
 * [GenaiInferenceClient] (bypassing the Flutter UI entirely) so
 * battery/thermal/memory can be measured without a human tapping through the
 * chat screen.
 *
 * Triggered only via:
 * ```
 * adb shell am broadcast -a org.esr.sidekick.AI_BENCH_RUN -p org.esr.sidekick \
 *   --es prompts "prompt one|prompt two|prompt three" --ei repeat 3
 * ```
 *
 * `android:exported="false"` in the manifest — that only blocks *other apps*
 * on the device from sending this broadcast; `adb shell` runs with ambient
 * shell privilege and can still reach it, which is exactly what
 * `tools/ai-bench.sh` relies on.
 *
 * DESIGN CONSTRAINT: foreground/on-demand only, same as the chat screen —
 * this creates its own short-lived [GenaiInferenceClient], runs the
 * requested prompts, and closes the model handle in `finally`. It does not
 * touch WorkManager, does not persist anything, and nothing survives once
 * the run completes.
 */
class AiBenchReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_RUN = "org.esr.sidekick.AI_BENCH_RUN"
        private const val TAG = "AiBenchReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RUN) return
        val promptsExtra = intent.getStringExtra("prompts")
        if (promptsExtra.isNullOrBlank()) {
            Log.w(TAG, "ai-bench: AI_BENCH_RUN received with no 'prompts' extra; ignoring")
            return
        }
        val repeatCount = intent.getIntExtra("repeat", 1).coerceAtLeast(1)
        val prompts = promptsExtra.split("|").map { it.trim() }.filter { it.isNotEmpty() }
        if (prompts.isEmpty()) {
            Log.w(TAG, "ai-bench: 'prompts' extra parsed to zero prompts; ignoring")
            return
        }

        // goAsync() extends the receiver's lifetime past onReceive() returning,
        // which we need since inference is genuinely asynchronous. Must call
        // pending.finish() exactly once, which we do in `finally` below.
        val pending = goAsync()
        val appContext = context.applicationContext
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            val inference = GenaiInferenceClient(appContext)
            try {
                val total = prompts.size * repeatCount
                Log.i(TAG, "ai-bench: starting $total prompt(s) ($repeatCount round(s))")
                var n = 0
                for (round in 1..repeatCount) {
                    for (prompt in prompts) {
                        n++
                        val start = System.currentTimeMillis()
                        try {
                            val text = inference.askOnce(prompt)
                            val elapsed = System.currentTimeMillis() - start
                            Log.i(
                                TAG,
                                "ai-bench: [$n/$total] ${elapsed}ms, ${text.length} chars back " +
                                    "for: ${prompt.take(60)}",
                            )
                            logFullText(n, text)
                        } catch (e: Throwable) {
                            Log.e(TAG, "ai-bench: [$n/$total] failed for: ${prompt.take(60)}", e)
                        }
                    }
                }
                Log.i(TAG, "ai-bench: loop complete ($total prompts)")
            } finally {
                inference.close()
                pending.finish()
            }
        }
    }

    /**
     * Logs the FULL response text for prompt [n], chunked to dodge logcat's
     * per-line size cap (~4076 bytes) and its ring-buffer/`-d` line cap.
     * Each line is prefixed `ai-bench-text[n][chunk/total] ` so a script can
     * reassemble the original string by filtering on tag+prefix, sorting by
     * chunk index, and concatenating.
     */
    private fun logFullText(n: Int, text: String) {
        val chunkSize = 3000
        if (text.isEmpty()) {
            Log.i(TAG, "ai-bench-text[$n][1/1] ")
            return
        }
        val chunks = text.chunked(chunkSize)
        val total = chunks.size
        chunks.forEachIndexed { idx, chunk ->
            Log.i(TAG, "ai-bench-text[$n][${idx + 1}/$total] $chunk")
        }
    }
}
