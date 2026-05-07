# Pulse — what changed

User-facing changelog for Mike's Pixel app. Most recent first. Top entries
also surface in-app on the About / Status screen.

## v0.2.1+6 — 2026-05-07

- **About / Status screen** — accessible from the (i) icon in the app bar.
  Shows version, build SHA, build timestamp, configured relay host, the
  host actually in use right now, a green/red reachability dot, last
  poll / last success times, last error, and the most recent changelog
  entries. Answers "what version is this and what is it talking to" in
  one tap.
- **Tailscale fallback added** — `100.72.65.118:3333` (Mac's Tailscale IP)
  is now in the default candidate list. Stream survives off-LAN and
  router-DHCP changes without you touching settings.
- **Stream health tracking** — Dee Stream client records last poll, last
  success, last error, and current entry count. Surfaced on About screen.
- **Changelog in-app** — this list is bundled into the build at compile
  time (`--dart-define BUILD_CHANGELOG=...`); falls back to a hardcoded
  list when not set.

## v0.2.0+5

- Per-segment response bars on Dee Stream cards (Mira-principle UX —
  tap-and-untap, no confirmation dialog).
- Phase 1b: Reply-to-Dee composer + `dispatch_input` client.
- Bug-fix bundle: alarm dismiss flow, Dee Stream long-message scroll,
  routine deletion, alarm tap-pin behavior.
- TDD pipeline added.

## v0.1.0+5 and earlier

- Phase 1a Dee Stream — readable & copyable Dee messages.
- Relay fallback chain + Test Connection button in settings.
- Calendar polling, alarmClock notifications, morning routine, webhook.
