---
compiled_by: Claude Sonnet 4.6 — soma-alarm CI fix & gap analysis — 2026-04-30
source_authors: Claude Sonnet 4.6, Mike Wolf
last_edited: Claude Sonnet 4.6 — soma-alarm CI fix & gap analysis — 2026-04-30
---

# soma-alarm ↔ Sidekick Gap Analysis

*Compiled 2026-04-29 by Claude Sonnet 4.6 — soma-alarm integration session.*  
*Source: `~/Projects/soma-alarm/README.md`, `~/Projects/Sidekick/REQUIREMENTS.md`, git log.*

---

## 1. What soma-alarm covers (requirements met)

| Sidekick req | Requirement text | soma-alarm implementation | Status |
|---|---|---|---|
| **N2** | Time-based reminders for external commitments | Reads on-device calendar, fires `AlarmManager.setAlarmClock` N min before each event. Doze-bypassing. Snooze (5/10 min) + Dismiss actions. T-0 follow-up alarm if not dismissed. | ✅ Built |
| **B1** (partial) | Morning routine accountability | 7am daily alarm + sqflite-backed checklist UI. Daily reset. Default items: Wear OMI / OMI charged / Limitless Pendant on / Phone charged. | ✅ Built (partial — see gaps) |
| **§4.1** SOMA relay | Phone-side SOMA integration | POSTs every alarm event (calendar lead + morning routine trigger) to the configured Contabo webhook endpoint. | ✅ Built (endpoint TBD) |
| **§2.2** Android surface | Android is the primary mobile device | Flutter / Material 3 app, targeting Mike's Pixel. The "Tasker vs. PWA vs. SMS" question is resolved. | ✅ Decided |
| **§4.4** Calendar (phone) | Calendar event awareness on phone | `device_calendar` reads on-device calendars without Google API tokens. 15-min periodic poll via WorkManager. | ✅ Built |

**Summary: soma-alarm is a complete implementation of the phone-alarm and morning-checklist slice of Sidekick.** It does exactly what N2 asks for and gives B1 a solid skeleton. The webhook integration means SOMA can observe alarm events on the Mac side.

---

## 2. What soma-alarm still needs to cover Sidekick fully

### 2.1 Hard gaps (features Sidekick requires that soma-alarm doesn't have)

| Sidekick req | What's missing | Notes |
|---|---|---|
| **C1** Idea dump (text) | No capture UI on the phone. No way to send a thought from the Pixel to the Mac-side GTD inbox. | Email transport is the current workaround (send to `claude@mike-wolf.com` with `[DISPATCH:Mac]` prefix). That's v1; a capture screen in soma-alarm is v1.5. |
| **C2** Idea dump (voice) | No mic/voice input in soma-alarm. | Long-press home → Google Assistant → email workaround works today; in-app voice would be native. |
| **B1** (full) Morning routine sequence | Current checklist items are hardware pendant checks, not the full morning routine. Missing: cold shower binary, wake-time log, martial arts prep confirmation. | Checklist items are configurable in the Settings; the schema supports custom items. Just needs the right defaults and a cold-shower checkbox. |
| **B2** Morning brief | soma-alarm fires the 7am alarm but doesn't display the day's calendar events or a single next-action. | The app already has the calendar data; a "today's agenda" card on the home screen is a small addition. |
| **B3** End-of-day prep | Not implemented. No evening routine or "tomorrow's first commitment" nudge. | Could be a second configurable alarm slot (same AlarmManager pattern). |
| **X1** Bidirectional sync | soma-alarm POSTs outbound alarm events via webhook. It does not pull Sidekick GTD state or tasks back to the phone. | Requires a Sidekick API or file-based sync endpoint. Out of scope for soma-alarm v1; plan for v2. |
| **N6** Escalation to Discord | If a lead alarm is dismissed/missed, there's no escalation path to Discord DM or HERMES. | AlarmManager callback could POST to SOMA webhook with a "dismissed" event; Mac-side Sidekick then escalates. Pattern already possible with the webhook. |
| **N3** Magic redirect line | No "what's the single most important thing you should focus on right now?" push notification from Sidekick → phone. | Requires a Sidekick → phone push channel. FCM (Firebase Cloud Messaging) is the standard path; would need a small server-side component. |
| **A4** Declared AFK | Phone has no way to tell Sidekick "I'm at the dojo" or "meditating now." | A one-tap AFK declaration button (posts to SOMA webhook with status payload) would cover this. |

### 2.2 Build / infrastructure gaps

| Issue | Impact | Fix |
|---|---|---|
| **CI failing** — Kotlin / Java 8 + WorkManager incompatibility in `.github/workflows/android.yml` | APK artifact not downloadable from GitHub Actions. Must do local `flutter build apk --release`. | Pin WorkManager to a version compatible with Java 8 in `android/app/build.gradle`; or bump `sourceCompatibility` / `targetCompatibility` to Java 11. One-line Gradle fix. |
| **No live-device test** on Mike's Pixel | Doze behavior, boot-receiver re-scheduling after reboot, and snooze-loop correctness are untested. | Side-load the APK, grant Calendar + Notifications + Exact Alarm permissions, run through a morning routine cycle and a calendar-event lead alarm. |
| **Webhook endpoint TBD** | soma-alarm POSTs to a placeholder URL. SOMA can't receive events until the real Contabo endpoint is configured. | Confirm SOMA inbound webhook URL, enter it in soma-alarm Settings. Verify with a manual alarm trigger. |

---

## 3. Recommended next 3 features to add to soma-alarm

Ordered by impact × implementation effort (lowest effort, highest Sidekick coverage first).

### Feature 1 — Fix CI + live-device test (unblock everything else)

**Why first:** Nothing else matters until the app actually runs on Mike's Pixel. The CI fix is a one-line Gradle change. The live-device test unblocks N2 and B1 validation.

**What to do:**
1. In `android/app/build.gradle`, bump `compileOptions` to Java 11 (or pin WorkManager to `2.7.x` which still supports Java 8).
2. Push to `main`, confirm CI produces a downloadable APK artifact.
3. Side-load on Mike's Pixel: grant Calendar, Notifications, Schedule Exact Alarm permissions.
4. Run a full morning routine cycle and watch it fire a calendar lead alarm.

**Sidekick requirements unblocked:** N2 ✅ confirmed, B1 ✅ confirmed, §4.1 webhook ✅ confirmed.

---

### Feature 2 — Full morning routine checklist + cold shower + wake log

**Why second:** B1 is the highest-frequency Sidekick habit loop. The checklist infrastructure (sqflite, daily reset) is already there — it just needs the right items and a wake-time input field.

**What to do:**
1. Add to the default checklist: "Cold shower" (binary), "Wake time" (time picker, logs actual vs. target 5–7:30am window).
2. Add "Martial arts today?" (binary — maps to H1).
3. On checklist completion, POST a structured payload to the SOMA webhook: `{"event":"morning_routine_complete","items":[...], "wake_time":"...", "cold_shower":true}`.
4. Mac-side Sidekick ingests this payload for B1 accountability.

**Sidekick requirements covered:** B1 (full), H1, H2.

---

### Feature 3 — One-tap AFK declaration + daily brief card

**Why third:** These two small features give soma-alarm a two-way Sidekick relationship instead of just outbound alarm POSTs.

**AFK declaration (A4):**
1. Add a persistent bottom-bar button: "I'm AFK / At dojo / Meditating" (cycles through states or opens a quick-pick).
2. On tap, POST `{"event":"afk_declared","status":"dojo","until":"..."}` to the SOMA webhook.
3. Mac-side Sidekick buffers notifications during declared AFK (A2).

**Daily brief card (B2):**
1. On the soma-alarm home page (already shows upcoming events), add a "Today's brief" card at the top: first calendar event + single next-action pulled from a Sidekick-owned JSON endpoint (e.g., `http://localhost:3334/sidekick/brief`).
2. This requires a thin Sidekick API on the Mac — a single GET endpoint that returns `{"next_action": "...", "first_commitment": {...}}`. mac-controller already serves on 3334; a new route is trivial.

**Sidekick requirements covered:** A4, B2.

---

## 4. Quick-reference: requirement coverage after all three features

| Req | Before features | After Feature 1 | After Feature 2 | After Feature 3 |
|---|---|---|---|---|
| N2 | Built, untested | ✅ Live-tested | ✅ | ✅ |
| B1 | Partial (pendant checks) | Partial | ✅ Full | ✅ |
| B2 | ❌ | ❌ | ❌ | ✅ |
| H1 | ❌ | ❌ | ✅ | ✅ |
| H2 | ❌ | ❌ | ✅ | ✅ |
| A4 | ❌ | ❌ | ❌ | ✅ |
| §4.1 webhook | Built, endpoint TBD | ✅ Live-confirmed | ✅ richer payload | ✅ |
| C1/C2 capture | ❌ | ❌ | ❌ | ❌ (v2 scope) |
| X1 bidirectional sync | ❌ | ❌ | ❌ | ❌ (v2 scope) |
| N6 escalation | ❌ | ❌ | ❌ | ❌ (v2 scope) |

After the three features above, soma-alarm covers the core phone surface for Sidekick's morning routine and awareness requirements. Capture (C1/C2), bidirectional sync (X1), and escalation (N6) are v2 scope and don't block the rest of Sidekick from shipping.
