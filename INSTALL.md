# soma-alarm — install on the Pixel

Built from `main` @ `16bd69e` via GitHub Actions (`Android APK` workflow, run `25169543716`, ✅ success 2026-04-30).

## Status snapshot

| Item | Status |
|---|---|
| APK | ✅ Downloaded — `~/Downloads/soma-alarm-apk/soma-alarm-release-apk/app-release.apk` (55 MB) |
| `adb` | ✅ Installed via Homebrew cask `android-platform-tools` (v37.0.0). `adb version` confirms. |
| Pixel connected? | ❌ Not yet — `adb devices` returned empty. Plug in + accept "Allow USB debugging" prompt on the phone. |
| Webhook URL | ⚠️ **Placeholder.** Default in-app is `https://contabo-host.example/soma/v1/alarm-event`. No real Contabo endpoint exists yet — see "Webhook blocker" below. |

## One-liner install (after plugging in the Pixel)

```bash
adb devices                     # confirm Pixel shows as "device" not "unauthorized"
adb install -r ~/Downloads/soma-alarm-apk/soma-alarm-release-apk/app-release.apk
```

If the Pixel hasn't been used with `adb` before:
1. Settings → About phone → tap "Build number" 7× to enable Developer options.
2. Settings → System → Developer options → enable "USB debugging".
3. Plug in, tap "Allow" on the RSA fingerprint prompt.

## Permissions to grant after first launch

The app uses runtime permissions; tap through these on first run (or grant via Settings → Apps → SOMA Alarm → Permissions):

- **Calendar** — read on-device calendars (for lead alarms).
- **Notifications** — post alarm + morning-routine notifications (Android 13+).
- **Schedule exact alarm** — required for `setAlarmClock`. Settings → Apps → SOMA Alarm → "Alarms & reminders" toggle.
- **Battery optimization exemption** (recommended) — Settings → Apps → SOMA Alarm → Battery → Unrestricted. Otherwise Doze can delay the WorkManager poll.

## First-run smoke test

1. Open the app. Confirm it lists upcoming calendar events on the home screen (give it a few seconds — the first calendar poll runs after grants).
2. Settings → set lead time to 1 minute, save.
3. Create a calendar event 2 minutes in the future. Wait. The alarm should fire ~1 minute before, full-screen, with snooze + dismiss actions.
4. Settings → set Morning Routine time to 2 minutes from now. Wait. The morning checklist should fire and let you tick items.
5. (Once webhook is real) Check the SOMA-side receiver got `event_id`, `title`, `scheduled_time`, `fired_time`, `action`, `source: "soma-alarm-android"` payloads.

## Webhook blocker

The Contabo `/soma/v1/alarm-event` endpoint **doesn't exist yet**. The audit at `~/Projects/SOMA/audits/2026-04-27-W2.1-calendar-alarm-app.md` flags this; the gap doc at `docs/SOMA-ALARM-GAP.md` §2.2 calls it out. Until that receiver is built (or Mike points the app at any other URL — ngrok, a Hermes route, whatever):

- The app still works end-to-end on the phone — alarms fire, checklists work.
- Webhook POSTs silently fail (errors swallowed by design — best-effort, 8s timeout).
- To override, open the app → Settings → Webhook URL → enter a real URL and save. No rebuild needed.

## If you need to rebuild

CI is wired: any push to `main` runs `.github/workflows/android.yml`, produces `soma-alarm-release-apk` artifact. Re-download with:

```bash
gh run list --workflow android.yml --branch main --limit 1
gh run download <run-id> --dir ~/Downloads/soma-alarm-apk
```
