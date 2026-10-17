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

# Loopback only (Locke review, 2026-10-16). `python3 -m http.server` binds
# every interface, so anyone on the same Wi-Fi could load Pulse. Its CLI takes
# one --bind address, so this inline server listens on 127.0.0.1 and on ::1
# (browsers resolve "localhost" to ::1 first).
echo "[$(date)] serving $BUILD_DIR on 127.0.0.1:$PORT and [::1]:$PORT"
exec /opt/homebrew/bin/python3 - "$BUILD_DIR" "$PORT" <<'PY'
import functools, http.server, socket, sys, threading

directory, port = sys.argv[1], int(sys.argv[2])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)

class V6Server(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6

v4 = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
try:
    v6 = V6Server(("::1", port), handler)
    threading.Thread(target=v6.serve_forever, daemon=True).start()
except OSError as e:
    print(f"[::1]:{port} unavailable ({e}); IPv4 loopback only", flush=True)
v4.serve_forever()
PY
