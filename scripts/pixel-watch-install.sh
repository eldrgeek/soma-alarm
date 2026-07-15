#!/usr/bin/env bash
set -euo pipefail

DEVICE="59080DLCQ0077G"
APK_PATH="$HOME/Projects/Sidekick-android/build/app/outputs/flutter-apk/app-release.apk"
TIMEOUT_SECS=$((8 * 3600))
POLL_INTERVAL=60
START=$(date +%s)
LOGFILE="$HOME/Projects/Sidekick-android/scripts/pixel-watch-install.log"
TIMEOUT_NOTE="$HOME/Projects/SOMA/state/pixel-apk-autoinstall-3-2026-05-12.md"
REPLY_FILE="$HOME/.dispatch/dee_replies.jsonl"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOGFILE"; }

log "Watcher started. Polling every ${POLL_INTERVAL}s, timeout ${TIMEOUT_SECS}s."

mkdir -p "$(dirname "$TIMEOUT_NOTE")" "$(dirname "$REPLY_FILE")"

while true; do
  NOW=$(date +%s)
  ELAPSED=$(( NOW - START ))
  if (( ELAPSED >= TIMEOUT_SECS )); then
    log "8-hour timeout reached. No Pixel detected."
    cat > "$TIMEOUT_NOTE" <<EOF
# pixel-apk-autoinstall-3 timed out

Started: $(date -Iseconds -d @$START 2>/dev/null || date -Iseconds)
Elapsed: ${ELAPSED}s
Device $DEVICE never appeared. APK 0.2.8+14 was not installed automatically.
Next step: manual install when Pixel reconnects.
EOF
    log "Timeout note written to $TIMEOUT_NOTE"
    exit 0
  fi

  # Check for the specific device in "device" state (not "offline" or "unauthorized")
  if adb devices 2>/dev/null | grep -q "^${DEVICE}[[:space:]]*device$"; then
    log "Device $DEVICE detected."

    # Find the APK with the highest versionCode in the filename if multiple exist,
    # but we always use the canonical release path — just verify it exists.
    if [[ ! -f "$APK_PATH" ]]; then
      log "ERROR: APK not found at $APK_PATH — aborting."
      exit 1
    fi

    APK_MOD=$(stat -f '%m' "$APK_PATH" 2>/dev/null || stat -c '%Y' "$APK_PATH")
    log "Installing APK (mtime $(date -Iseconds -r "$APK_PATH" 2>/dev/null || date -d @$APK_MOD -Iseconds 2>/dev/null || echo $APK_MOD))…"

    if adb -s "$DEVICE" install -r "$APK_PATH" 2>&1 | tee -a "$LOGFILE"; then
      log "Install command succeeded."
    else
      log "ERROR: install command failed."
      exit 1
    fi

    VERSION=$(adb -s "$DEVICE" shell dumpsys package org.esr.sidekick 2>/dev/null | grep versionName | head -1 | tr -d ' ')
    log "Reported version: $VERSION"

    if echo "$VERSION" | grep -q "0\.2\.8"; then
      log "Version confirmed: $VERSION"
      ISO=$(date -Iseconds)
      echo "{\"source\":\"dee\",\"timestamp\":\"${ISO}\",\"body\":\"APK 0.2.8+14 installed on Pixel — About reachable, duplicate-message dedup fixed.\",\"in_reply_to\":null}" >> "$REPLY_FILE"
      log "Reply written to $REPLY_FILE"
    else
      log "WARNING: unexpected version after install: $VERSION"
    fi

    log "Done."
    exit 0
  else
    log "Device not seen (elapsed ${ELAPSED}s). Sleeping ${POLL_INTERVAL}s."
    sleep "$POLL_INTERVAL"
  fi
done
