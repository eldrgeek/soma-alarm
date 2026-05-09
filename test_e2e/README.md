# Pulse E2E Tests

Playwright tests for the Pulse Flutter web app served at `http://localhost:8088`.

## Prerequisites

1. Pulse built and served: `flutter build web && python3 -m http.server 8088 --directory build/web`
2. Yeshie relay running on port 3333 (provides the `/health` endpoint)
3. Node + npx available

## Install

```sh
cd ~/Projects/Sidekick-android
npm install
npx playwright install chromium
```

## Run

```sh
cd ~/Projects/Sidekick-android
npx playwright test test_e2e/
```

## Tests

- **A** — HTTP 200 + no `UnimplementedError` console messages
- **B** — No red `UnimplementedError` banner visible in page text
- **C** — Health screen renders with at least one service pill; saves screenshot to `~/Projects/SOMA/audits/screenshots/`
