# Sidekick (Android)

Android (Flutter) calendar alarm + morning routine app for the SOMA stack.

Pulse also includes a Meta Ray-Ban glasses voice bridge for conversations, strategic panels, and work dispatch across Mike's SOMA AI team. See [docs/META-GLASSES-MVP.md](docs/META-GLASSES-MVP.md).

Pulse also includes an on-device AI chat (v0, offline, no relay round-trip) — see [On-device AI chat](#on-device-ai-chat-v0-offline) below.

## What it does

- Reads on-device calendars (no Google API tokens — uses `device_calendar`).
- Polls every 15 min for events in the next 24h.
- Fires a **lead alarm** N minutes before each event (default 15) via Android `AlarmManager.setAlarmClock` (Doze-bypassing).
- Notification actions: **Snooze 5 / Snooze 10 / Dismiss**.
- A second alarm fires at T-0 unless dismissed.
- **Morning routine** alarm at 7am daily with a checklist UI (sqflite, daily reset).
  - Defaults: Wear OMI / OMI charged? / Limitless Pendant on? / Phone charged?
- POSTs every alarm event to the configured SOMA webhook.

## Stack

Flutter • Material 3 (dark default) • `device_calendar` • `flutter_local_notifications` (alarmClock mode) • `workmanager` (15-min periodic poll) • `sqflite` • `http` • `shared_preferences`.

## First-run setup — IMPORTANT for Mike

Before the build/dev workflow can succeed on macOS, grant the relevant macOS access in **System Settings → Privacy & Security**:

- **Calendar** → Terminal / Claude Code / your IDE (so dev workflows can introspect)
- **Microphone** → Terminal / Claude Code (for voice integrations downstream)
- **Camera** → Terminal / Claude Code (for capture-based test paths)
- **Accessibility** → Terminal / Claude Code (so AX-driven mac-controller tooling works alongside this repo)

These do not affect the Pixel install, but they unblock the surrounding SOMA dev tooling on the Mac. (The runtime Pixel permissions — Calendar read, notifications, exact-alarm — are requested by the app itself on first launch.)

## Build

The Meta DAT dependency requires a GitHub classic PAT with `read:packages` in untracked `android/local.properties` as `github_token=...`; see the glasses MVP guide.

```bash
flutter pub get
flutter build apk --release
```

CI builds an APK on every push to `main` (see `.github/workflows/android.yml`); download from the workflow run's artifacts.

## Configuration

Webhook URL, lead time, morning alarm time, and morning enable toggle live in **Settings** inside the app. Default webhook is a placeholder; change it to the real Contabo endpoint once the SOMA inbound route is live.

## Layout

```
lib/
  main.dart                # entry + WorkManager setup
  src/
    app.dart               # MaterialApp / theme
    home_page.dart         # upcoming events + scheduled alarms
    settings.dart          # SharedPreferences wrapper
    settings_page.dart     # settings UI
    calendar.dart          # device_calendar reader
    alarms.dart            # notifications, scheduling, action handling
    background.dart        # WorkManager poll body
    webhook.dart           # SOMA webhook POST
    checklist.dart         # sqflite repo
    checklist_page.dart    # routine + items UI
android/                   # Android scaffold (manifest with all permissions)
.github/workflows/         # APK CI
```

## On-device AI chat (v0, offline)

A chat screen (tap the lightning-bolt icon on the **Pulse** tab) backed by
Google's ML Kit **GenAI Prompt API** — Gemini Nano running locally via
AICore. No network call, no relay, works offline. Requires a device with
AICore support (verified supported: Pixel 10 Pro XL, Android 16 / SDK 36,
Tensor G5). On unsupported devices the screen shows an explanation instead
of crashing — the rest of the app is unaffected either way.

**Files:**
- `lib/src/on_device_assistant.dart` — the `OnDeviceAssistant` seam +
  `MlKitGenaiAssistant` implementation. A different on-device backend
  (flutter_gemma, a LiteRT-LM `.task` model, etc.) can slot in later by
  implementing the same interface — no UI changes needed.
- `lib/src/on_device_chat_screen.dart` — the chat UI. Handles all four
  feature states: unsupported platform, unavailable device, needs
  model-download, and available/chatting.
- `android/app/src/main/kotlin/org/esr/sidekick/GenaiInferenceClient.kt` —
  Flutter-agnostic wrapper around `com.google.mlkit:genai-prompt`.
- `android/app/src/main/kotlin/org/esr/sidekick/OnDeviceAssistantBridge.kt` —
  the Flutter platform channel (method + 2 event channels) wrapping the
  client above.
- `android/app/src/main/kotlin/org/esr/sidekick/AiBenchReceiver.kt` — a
  debug-only broadcast receiver used only by `tools/ai-bench.sh` (see below).

**Why a hand-rolled platform channel, not the `google_mlkit_genai_prompt`
pub.dev plugin:** that plugin's native `runInference` is a hardcoded stub
that always errors (`"Prompt API inference not yet fully implemented"`) and
its `runInferenceStreaming` isn't wired up at all, as of the published 0.2.0
/ develop branch (verified by reading its Kotlin source directly,
2026-07-26). We call `com.google.mlkit:genai-prompt:1.0.0-beta2` ourselves —
same pattern as the existing `MetaGlassesBridge.kt` — and get real token
streaming in the process. Full rationale in the doc comment at the top of
`lib/src/on_device_assistant.dart`.

**Design constraint (enforced in code comments at every layer):** inference
is strictly foreground and on-demand. Nothing here is registered with
WorkManager's existing 15-min calendar poll (`lib/src/background.dart`); the
native model handle is created lazily per screen visit and closed when the
screen closes or `tools/ai-bench.sh`'s scripted run finishes. No background
inference, ever.

### Battery/thermal/memory benchmark — `tools/ai-bench.sh`

Run **only** with the Pixel attached over USB, unlocked, and not in active
use — it drives real on-device inference in a loop:

```bash
tools/ai-bench.sh                          # defaults: 3 prompts x 3 rounds
tools/ai-bench.sh --prompts "a|b|c" --repeat 5 --out /tmp/report.md
```

It refuses to run with no device attached (or with more than one attached —
set `ANDROID_SERIAL` to disambiguate). It unplugs + resets battery stats,
fires the scripted prompt loop via the `AI_BENCH_RUN` broadcast (received by
`AiBenchReceiver.kt`, which calls `GenaiInferenceClient` directly — the chat
UI doesn't need to be open), polls `dumpsys meminfo` for peak PSS while
watching logcat for completion, then collects
`dumpsys batterystats --charged org.esr.sidekick`, `dumpsys thermalservice`,
and a final `dumpsys meminfo` snapshot into a markdown report under
`tools/ai-bench-reports/`. It always restores battery state
(`dumpsys battery reset`) on exit, including on early failure.

## Open work

- Live-device testing on Mike's Pixel (permissions, Doze behavior, snooze loop, boot-receiver re-scheduling).
- Confirm Contabo webhook endpoint shape and auth.
- Add Wave-1 OMI / Limitless integrations once those land.
