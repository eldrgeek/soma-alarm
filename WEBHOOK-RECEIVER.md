# Webhook Receiver — Investigation & Recommendation

*2026-04-30 — Claude Opus 4.6 analysis*

---

## 1. What the phone sends

**Single endpoint.** `WebhookClient.post()` in `lib/src/webhook.dart` sends to one
configurable URL (default placeholder: `https://contabo-host.example/soma/v1/alarm-event`).

**Method:** `POST`

**Headers:** `Content-Type: application/json` only.

**Auth:** None. No bearer token, no HMAC signature, no API key header. The request is
unauthenticated.

**Timeout:** 8 seconds. Errors are swallowed (best-effort fire-and-forget).

**Payload shape:**

```json
{
  "event_id": "string — calendar event stable ID or 'morning-2026-04-30'",
  "title": "string — event title or 'Morning routine'",
  "scheduled_time": "ISO 8601 UTC",
  "fired_time": "ISO 8601 UTC",
  "action": "fire | snooze5 | snooze10 | dismiss | morning",
  "location": "string (optional, only if calendar event has one)",
  "source": "soma-alarm-android"
}
```

**Frequency:** Low volume. One POST per alarm interaction — typically 4–10/day
(morning alarm + 1–3 calendar events × lead + T-0 + possible snooze/dismiss actions).

**Trigger points in code:**
- `alarms.dart:240–248` — morning routine notification tapped → action `morning`
- `alarms.dart:251–258` — calendar alarm fired/interacted → action is `fire`, `snooze5`, `snooze10`, or `dismiss`

---

## 2. Hosting options ranked

### Option A — Contabo VPS (recommended)

**What's there:** Node.js v22, pm2, nginx. Two services running: `frontrow-server` (LiveKit)
and `scs-api` on port 4242 (proxied at `/api/scs/`). DNS via `vpsmikewolf.duckdns.org`.

| Dimension | Assessment |
|---|---|
| Cost | $0 incremental — VPS is already paid for |
| Latency | ~50–100ms from Pixel (Denver → Contabo EU) — fine for async events |
| Persistence | Full disk; can write to SQLite or flat files |
| Secrets | `.env` files on disk, same pattern as scs-api |
| Ease of deploy | `scp` + `pm2 restart`, or git clone + pm2. Same as scs-api |
| Ease of teardown | `pm2 delete soma-webhook` |
| HTTPS | Already have nginx + Let's Encrypt for the domain |

**Risk:** Single point of failure (one VPS), but these are best-effort alarm events, not
transactions. Acceptable.

### Option B — Sidekick local (Mac) + Tailscale/ngrok

Sidekick (`~/Projects/Sidekick/sidekick.py`) runs locally on the Mac. The HUD relay is on
`localhost:3333`. Could add an HTTP endpoint.

| Dimension | Assessment |
|---|---|
| Cost | $0 if using Tailscale (free tier); ngrok free tier has URL rotation |
| Latency | Lowest if on same Tailscale network |
| Persistence | Mac disk |
| Downside | **Mac must be awake and Sidekick must be running.** Mike's laptop sleeps, travels, reboots. Alarm events would be lost during downtime. Also requires Tailscale on the Pixel. |
| Ease of teardown | Kill the process |

**Verdict:** Fragile for a phone-to-server path. Good as a *secondary* consumer (Contabo
forwards to Mac when it's reachable), bad as primary receiver.

### Option C — Cloudflare Workers

| Dimension | Assessment |
|---|---|
| Cost | Free tier: 100K requests/day (more than enough) |
| Latency | Edge — lowest possible |
| Persistence | Workers KV or D1 for event log |
| Secrets | Wrangler secrets |
| Downside | Another service to manage. No existing Cloudflare account in the stack. Adds a dependency outside Mike's infra. |
| Ease of teardown | `wrangler delete` |

**Verdict:** Overengineered for 5–10 requests/day. Makes sense if Contabo goes away.

### Option D — Pipedream / Vercel / Railway

| Dimension | Assessment |
|---|---|
| Cost | Free tiers available |
| Latency | Fine |
| Persistence | Limited on free tiers (Pipedream: 100 events/day free, Vercel: serverless = no persistent state without a DB addon) |
| Downside | Third-party dependency, account management, cold starts. Vercel needs a DB for persistence. |
| Ease of teardown | Delete project |

**Verdict:** Unnecessary complexity given Contabo exists and has capacity.

---

## 3. Recommendation: Contabo VPS

**Why:**
1. Already running, already has Node + pm2 + nginx + HTTPS.
2. The scs-api is a working template for the exact pattern needed (Express + SQLite + pm2 + nginx proxy).
3. Zero incremental cost.
4. Mike already has SSH access and a deployment pattern.
5. All downstream consumers (Discord bot, Hermes, Yeshie relay) are easier to reach from a persistent server than from a serverless function.

The only scenario where Contabo is wrong is if the VPS goes away or if Mike wants zero-ops.
In that case, Cloudflare Workers is the fallback.

---

## 4. Contabo deployment specifics

**Existing services:**
- `frontrow-server` at `/opt/frontrow-server/`
- `scs-api` at `/opt/scs-api/` on port 4242, proxied at `/api/scs/`

**Recommended port:** 4243 (next after scs-api's 4242).

**Recommended path:** `/opt/soma-webhook/`

**nginx proxy:** Add a location block to the existing nginx config:
```
location /soma/v1/ {
    proxy_pass http://127.0.0.1:4243/;
}
```

This gives the phone endpoint: `https://vpsmikewolf.duckdns.org/soma/v1/alarm-event`

**Deploy mechanism:** Same as scs-api:
1. `git clone` (or scp) to `/opt/soma-webhook/`
2. `npm install --production`
3. `pm2 start index.js --name soma-webhook`
4. `pm2 save`
5. Reload nginx

---

## 5. Minimum viable receiver

### Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/alarm-event` | Receive alarm events from the phone |
| `GET` | `/health` | Liveness check |
| `GET` | `/events?since=ISO&limit=N` | Query recent events (debugging + Sidekick pull) |

### Behaviors on receiving an event

1. **Validate** — check required fields (`event_id`, `title`, `action`, `source`). Return 400 if malformed.
2. **Log to SQLite** — append to an `events` table with `id, event_id, title, action, scheduled_time, fired_time, location, source, received_at`. This is the persistence layer.
3. **Notify Discord** — POST to Mike's Discord channel via the bot token in `~/.hermes/.env`. Format: one-line summary like `"🔔 soma-alarm: Meeting with Jan — fire (15min lead)"`. Only for `fire` and `morning` actions; skip `snooze` and `dismiss` to reduce noise.
4. **Forward to Yeshie relay** (optional, future) — POST to `localhost:3333/jobs/update` if SOMA orchestration wants to react to alarm events. Not MVP.

### What it should NOT do (yet)

- No auth enforcement on inbound (the phone sends no token; add later if needed).
- No FCM push back to the phone (that's a separate feature for N3 magic redirects).
- No Sidekick task updates (wait for bidirectional sync design in v2).

### Tech stack

- **Node.js** (already on VPS, matches scs-api pattern)
- **Express** (or Fastify — either works for 3 routes)
- **better-sqlite3** (synchronous, simple, same pattern as scs-api)
- ~50 lines of code for MVP

---

## 6. Open questions for Mike

1. **Auth:** The phone currently sends no authentication. Is that acceptable for MVP (security-through-obscurity on a personal VPS), or should we add a shared secret header (`X-SOMA-Token`) now? Adding it later means updating the phone app too.

2. **Discord channel:** Which Discord channel should alarm notifications go to? The Hermes `.env` has the bot token. Need a channel ID.

3. **Event retention:** How long to keep events in SQLite? 30 days with auto-prune, or keep forever (volume is tiny)?

4. **Snooze/dismiss noise:** Should Discord be notified on snooze and dismiss actions, or only on `fire` and `morning`? (Recommendation: fire + morning only.)

5. **Forward to Mac:** Should the Contabo receiver attempt to forward events to the Mac (Yeshie relay at `localhost:3333` or Sidekick) when reachable? This would require Tailscale or a reverse tunnel. Or should the Mac-side pull from `/events?since=...` on a schedule?

6. **Naming:** The default URL placeholder is `/soma/v1/alarm-event`. Confirm this path, or change to something else before it's baked into the phone app settings.
