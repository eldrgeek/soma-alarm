#!/bin/bash
# Pulse web dev server with hot-reload on file save.
# Replaces the static `python3 -m http.server 8088 -d build/web` setup.
# Run this from project root; reload with browser refresh after saving a .dart file.

set -e
cd "$(dirname "$0")/.."

# Free the port if a static server (or stale flutter run) is holding it
EXISTING=$(lsof -ti :8088 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  echo "freeing :8088 (was PID $EXISTING)"
  kill "$EXISTING" 2>/dev/null || true
  sleep 1
fi

# flutter run -d web-server keeps a hot-reload-aware build pipeline alive.
# Browser refresh picks up the latest. Logs go to /tmp/pulse-web-dev.log.
echo "starting flutter dev server on http://localhost:8088 (logs: /tmp/pulse-web-dev.log)"
nohup /opt/homebrew/bin/flutter run -d web-server \
  --web-port=8088 \
  --web-hostname=localhost \
  --no-web-resources-cdn \
  > /tmp/pulse-web-dev.log 2>&1 &

echo "PID: $!"
echo "tail logs:  tail -f /tmp/pulse-web-dev.log"
echo "stop:       kill \$(lsof -ti :8088)"
