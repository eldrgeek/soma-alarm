# SOMA Alarm

Android (Flutter) calendar alarm + morning routine app for the SOMA stack.

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

## Open work

- Live-device testing on Mike's Pixel (permissions, Doze behavior, snooze loop, boot-receiver re-scheduling).
- Confirm Contabo webhook endpoint shape and auth.
- Add Wave-1 OMI / Limitless integrations once those land.
