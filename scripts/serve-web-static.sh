#!/bin/bash
# Pulse static web serve — for launchd-managed always-on use.
# Serves ~/Projects/Sidekick-android/build/web/ on port 8088.
# If build/web is missing, builds first.
# Foreground process so launchd KeepAlive can supervise.

set -u

PROJECT_DIR="$HOME/Projects/Sidekick-android"
BUILD_DIR="$PROJECT_DIR/build/web"
PORT=8088

cd "$PROJECT_DIR"

# Ensure build exists. flutter build is slow; only run if missing.
if [ ! -f "$BUILD_DIR/main.dart.js" ]; then
  echo "[$(date)] build/web missing, running flutter build web"
  /opt/homebrew/bin/flutter build web --pwa-strategy=none
fi

# Free port if a stale process owns it (e.g. dev flutter run from earlier session)
EXISTING=$(lsof -ti :$PORT 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  echo "[$(date)] freeing :$PORT (PID $EXISTING)"
  kill "$EXISTING" 2>/dev/null || true
  sleep 1
fi

echo "[$(date)] serving $BUILD_DIR on :$PORT"
exec /opt/homebrew/bin/python3 -m http.server $PORT --directory "$BUILD_DIR"
