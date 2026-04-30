# soma-alarm — next steps

Prioritized from `docs/SOMA-ALARM-GAP.md` for the next work session. Order optimizes for *Sidekick coverage gained per hour of work*.

## Tier 1 — do first (unblockers, hours of work each)

### 1. Stand up the SOMA webhook receiver

**Why first:** Without it, soma-alarm's outbound POSTs (the whole point of §4.1 SOMA relay) hit nothing. The app is already POSTing — the receiver is the missing half.

**What:** Single HTTP POST endpoint on Contabo (`vpsmikewolf.duckdns.org`) at `/soma/v1/alarm-event`. Accepts the payload shape documented in `lib/src/webhook.dart` (`event_id`, `title`, `scheduled_time`, `fired_time`, `action`, optional `location`, `source`). Persist to a JSONL log + tee to Discord/Hermes for observation. Then point the Settings → Webhook URL field at the real URL.

**Effort:** 1–2 hours (Node/Python service + pm2 + nginx route). VPS setup is in `~/Projects/CLAUDE.md`.

### 2. Live-device validation on the Pixel

**Why:** Doze, boot-receiver re-scheduling, snooze loops are all untested on real hardware. CI proves it compiles, not that it actually fires alarms reliably across reboots and overnight Doze.

**What:** Install via `INSTALL.md`, run the smoke test, then leave it overnight with a 7am alarm. Reboot the phone mid-day, confirm the alarm survives. Watch a real morning calendar event lead-alarm fire.

**Effort:** 30 min active + overnight soak.

## Tier 2 — capture (C1 / C2) — highest user-facing value

The README/gap doc both flag C1/C2 (idea dump, text + voice) as the most-missed Sidekick capability on the phone. Today's workaround is "email yourself with `[DISPATCH:Mac]`" — that works but it's friction.

### 3. C1 — Capture screen (text idea dump)

**What:** New tab in soma-alarm. Single big text field + Send button. On send, POST to SOMA webhook with `{"event":"capture","kind":"text","body":"...","captured_at":"..."}`. Mac-side Sidekick routes to the GTD inbox.

**Effort:** 2–3 hours. Tab + form + reuse `WebhookClient`. No new permissions.

**Bonus:** Add a home-screen widget or quick-settings tile so capture is one tap from anywhere.

### 4. C2 — Voice capture

**What:** Mic button on the capture screen. Use Android's built-in `SpeechRecognizer` (no cloud API key needed; on-device on Pixel). Transcribed text goes through the same capture POST as C1, with `"kind":"voice"`.

**Effort:** 3–4 hours including the runtime mic permission flow and a record→transcribe→confirm UX.

## Tier 3 — full B1 morning routine

### 5. Morning checklist defaults + cold shower + wake-time log

Per `SOMA-ALARM-GAP.md` Feature 2:
- Replace pendant-only defaults with the full Sidekick morning routine items.
- Add "Cold shower" binary, "Wake time" picker (logs vs. 5–7:30am target), "Martial arts today?" binary.
- On checklist completion, POST `{"event":"morning_routine_complete","items":[...],"wake_time":"...","cold_shower":true,"martial_arts":true|false}` to webhook.

**Effort:** 2 hours (sqflite schema is already there; just defaults + 2 new field types).

**Sidekick coverage:** B1 (full), H1, H2.

## Tier 4 — bidirectional + ambient

### 6. AFK declaration button (A4)

Persistent bottom-bar button cycling through "Available / AFK / Dojo / Meditating". Each tap POSTs `{"event":"afk_declared","status":"...","until":"..."}`. Sidekick uses this to gate notifications (A2). 1–2 hours.

### 7. Daily brief card (B2)

Top-of-home-screen card showing today's first commitment + a "next action" pulled from a Sidekick GET endpoint (e.g., `http://vpsmikewolf.duckdns.org/sidekick/brief` or LAN-only `localhost:3334/sidekick/brief` via mac-controller). Requires a thin Mac-side endpoint. 2 hours app-side + ~1 hour server-side.

### 8. End-of-day prep (B3)

Second configurable alarm slot, evening routine checklist, "tomorrow's first commitment" preview. Same AlarmManager pattern as the morning slot. 2–3 hours.

## v2 scope (parked)

- **X1** Bidirectional sync — needs a real Sidekick API. Defer until Sidekick has a stable shape.
- **N6** Discord escalation on missed alarms — partially possible today (POST a `dismissed_late` event from the webhook receiver to Discord); deeper escalation is a Mac-side concern.
- **N3** Magic redirect line — needs FCM + a Sidekick→phone push channel. Real effort; defer.

## Suggested order for tomorrow

1. Build the webhook receiver (Tier 1.1) — ~1.5 h.
2. Side-load + smoke test (Tier 1.2) — 30 min + overnight soak.
3. Start C1 capture screen (Tier 2.3) — 2–3 h.

That gets soma-alarm from "compiles" to "actually serving Sidekick" in one session.
