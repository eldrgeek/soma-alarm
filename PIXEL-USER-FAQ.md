# SOMA Alarm — Pixel User FAQ

Answers based on reading `lib/` source as of 2026-04-30.

---

## 1. Save button behavior on Settings screen

The Save button handler is `_save()` at `lib/src/settings_page.dart:43`.

**It does NOT navigate back.** On success it shows a `SnackBar` with "Saved." (line 57–59) and stays on the settings screen. There is **no error handling** — `_save()` is `async` but has no `try/catch`. If any `await` throws (e.g. `runBackgroundPoll()` fails because calendar permission was denied), the exception propagates unhandled — no error snackbar, no user feedback. The `if (!mounted) return` guard at line 56 only prevents showing the snackbar if the widget was disposed; it doesn't catch errors.

**Summary:** Save → stays on settings page, shows "Saved." snackbar. No navigation. No error UI.

---

## 2. How to trigger a webhook POST (testing)

**There is no "Test webhook" button.** The webhook only fires when a notification action is handled — specifically in `AlarmService._handleResponse()` at `lib/src/alarms.dart:236`. The `WebhookClient.post()` call (`lib/src/webhook.dart:7`) requires an alarm notification to actually fire and the user to interact with it (or for it to auto-fire).

**Lowest-friction ways to trigger a POST:**

1. **Schedule a calendar event starting in the next few minutes** (e.g. 5 minutes from now). Open the app, pull-to-refresh on the home screen. The app will poll calendars, find the event, and schedule a lead alarm (default 15 min before) plus a T-0 alarm. If the event is <15 min away, the lead alarm fires almost immediately as a notification. Tapping the notification or any action button (Snooze 5, Snooze 10, Dismiss) triggers the webhook POST.

2. **Set the lead time to 60 minutes** in Settings (`lib/src/settings_page.dart:91`, dropdown options: 5/10/15/20/30/60), then create an event within the next hour. The lead alarm fires sooner.

3. **Enable the morning alarm** and set it to a time 1–2 minutes from now. When the morning notification fires and you tap it, `_handleResponse` sends a webhook POST with `action: "morning"` (`lib/src/alarms.dart:240–247`).

**Important:** The webhook is best-effort — errors are silently swallowed (`lib/src/webhook.dart:33–34`). If your POST URL is wrong, you won't see any error in the app.

---

## 3. "No events and no alarms" — calendar reading

### Permission required

The app needs **`READ_CALENDAR`** runtime permission (declared in `AndroidManifest.xml:2`). The `device_calendar` plugin requests it at runtime via `_plugin.requestPermissions()` in `CalendarReader.ensurePermissions()` (`lib/src/calendar.dart:24–29`).

**Check:** Go to Android Settings → Apps → SOMA Alarm → Permissions → Calendar. It must say "Allowed." If the permission was denied, the app silently returns an empty list (line 35: `if (!await ensurePermissions()) return const []`). No error is shown to the user.

### Which calendars does it read?

**All of them.** `CalendarReader.upcomingEvents()` calls `_plugin.retrieveCalendars()` (line 36) and iterates over every calendar returned by the OS (`lib/src/calendar.dart:40`). There is no calendar selection UI — it reads every calendar the device exposes.

### Time window

**24 hours from now.** The default `window` parameter is `Duration(hours: 24)` (`lib/src/calendar.dart:33`). Events are filtered to `now < start < now+24h` (lines 50). **All-day events are excluded** (line 51: `if (e.allDay == true) continue`).

### Refresh mechanism

- **Manual refresh button** in the AppBar (`lib/src/home_page.dart:66–68`)
- **Pull-to-refresh** via `RefreshIndicator` wrapping the ListView (`lib/src/home_page.dart:70`)
- **Auto-refresh on app open:** `_refresh()` is called in `initState()` (`lib/src/home_page.dart:27–28`)
- **Background poll every 15 minutes** via Android WorkManager (`lib/main.dart:19–24`), which calls `runBackgroundPoll()` → `CalendarReader().upcomingEvents()`
- **No auto-refresh while the app is in foreground** beyond the initial load — there's no timer-based refresh

### Google account / calendar provider

The `device_calendar` plugin reads from the **Android Calendar Provider** (`content://com.android.calendar`), which aggregates all synced calendar accounts. If Mike's Google Calendar events show in the stock Android Calendar app, they should show here too.

**Most likely cause of "no events":** the app doesn't have the Calendar runtime permission. On first launch, the permission dialog may have been dismissed or denied. Pull-to-refresh should re-trigger the permission request (via `ensurePermissions()` at `lib/src/home_page.dart:31`), but if permanently denied, the user must grant it manually in Android Settings.

---

## 4. Alarm lifecycle

### When are alarms scheduled?

Alarms are scheduled by `runBackgroundPoll()` in `lib/src/background.dart:5`:

1. **On app startup:** `HomePage.initState()` → `_refresh()` → `runBackgroundPoll()` (`lib/src/home_page.dart:28,33`)
2. **On manual refresh / pull-to-refresh:** same path (`lib/src/home_page.dart:66–68,70`)
3. **On Settings Save:** `_save()` calls `runBackgroundPoll()` (`lib/src/settings_page.dart:49`)
4. **Every ~15 minutes in background:** WorkManager periodic task registered at app startup (`lib/main.dart:19–24`). Note: Android may throttle this to longer intervals depending on Doze mode and battery optimization.

### How many alarms per event?

**Two alarms per calendar event** (`lib/src/background.dart:21–39`):

1. **Lead alarm** (`isLeadAlarm: true`): fires `leadMinutes` before the event start time (line 21–29)
2. **Start alarm** (`isLeadAlarm: false`): fires at the event's actual start time (line 30–38)

Each alarm is only scheduled if its time is still in the future (lines 22, 31).

### What determines lead time?

The `leadMinutes` setting, stored in SharedPreferences (`lib/src/settings.dart:58–60`). Default is **15 minutes**. Configurable in Settings via a dropdown with options: 5, 10, 15, 20, 30, 60 minutes (`lib/src/settings_page.dart:91`).

### Manual alarm UI?

**No.** There is no manual "set alarm" button. Alarms are **purely calendar-driven** — the only way to get an event alarm is to have a matching calendar event in the next 24 hours.

### Stale alarm cleanup

`runBackgroundPoll()` compares currently-scheduled alarm IDs against live calendar event IDs and cancels any that no longer match (`lib/src/background.dart:13–18`). This means deleted or moved calendar events get their alarms cleaned up on the next poll.

### Morning routine alarm

Scheduled separately from calendar alarms:

- **When scheduled:** during `runBackgroundPoll()` (lines 42–49) and also directly from `_save()` in Settings (`lib/src/settings_page.dart:50–55`)
- **Configurable from UI:** Yes — Settings has a toggle ("Daily morning alarm") and a time picker (`lib/src/settings_page.dart:99–120`)
- **Default:** enabled at 07:00 (`lib/src/settings.dart:46–48`)
- **Recurrence:** uses `matchDateTimeComponents: DateTimeComponents.time` (`lib/src/alarms.dart:197`), which makes it repeat daily at the same time
- **Notification ID:** fixed at `0xCAFE` (`lib/src/alarms.dart:188`)
- **Webhook:** tapping the morning notification fires a webhook POST with `action: "morning"` (`lib/src/alarms.dart:240–247`)

### Notification actions

Event alarm notifications include three action buttons (`lib/src/alarms.dart:117–124`):
- **Snooze 5** — reschedules the alarm 5 minutes from now
- **Snooze 10** — reschedules the alarm 10 minutes from now
- **Dismiss** — cancels both lead and start alarms for that event

All three actions trigger a webhook POST before executing.

---

FAQ COMPLETE
