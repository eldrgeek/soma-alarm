---
district: omi-hardware
status: active
capabilities: [flutter, android-alarms, calendar, soma-webhook, ota]
last_reviewed: 2026-06-23
---

# Sidekick-android — Flutter calendar-alarm + morning-routine app (brand: Pulse) for the SOMA stack

**Where work happens:** `lib/main.dart` (entry + WorkManager) · `lib/src/alarms.dart` (scheduling + actions) · `lib/src/calendar.dart` (device calendar) · `lib/src/background.dart` (15-min poll) · `lib/src/webhook.dart` (SOMA POST) · `android/` (manifest/permissions)

**Key docs** (read in this order):
- [README.md](README.md) — what it does, stack, build, layout
- [docs/SOMA-ALARM-GAP.md](docs/SOMA-ALARM-GAP.md) — alarm behavior gaps vs SOMA needs
- [pulse/PIXEL-INTEGRATION.md](pulse/PIXEL-INTEGRATION.md) — Pulse/Pixel integration
- [WEBHOOK-RECEIVER.md](WEBHOOK-RECEIVER.md) — webhook contract

**Skills**
- gap: Flutter/Android build-and-OTA-release procedure (pub get → build apk → CI artifact → OTA stamp) is recurring and non-obvious — candidate for a local skill.

**Depends on / used by:** posts alarm events to the SOMA inbound webhook (Contabo endpoint, TBD); part of the SOMA morning-routine surface. Wave-1 OMI / Limitless integrations pending.

**Gotchas**
- pubspec name is `sidekick`, package dir is `soma_alarm_android`, user-facing brand is **Pulse** — three names for one app.
- `.claude/worktrees/*` hold many stale duplicate copies of these docs — edit only the repo-root files, never a worktree copy.
- Lead alarm uses `AlarmManager.setAlarmClock` to bypass Doze; runtime perms (calendar, notifications, exact-alarm) are requested on first Pixel launch, separate from the macOS dev grants in README.
