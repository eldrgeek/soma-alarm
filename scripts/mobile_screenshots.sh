#!/usr/bin/env bash
# mobile_screenshots.sh — capture Pulse mobile UI screenshots and build contact sheet
#
# Modes:
#   ./scripts/mobile_screenshots.sh android   — ADB screencap from real Android device
#   ./scripts/mobile_screenshots.sh ios        — flutter drive on real iPhone
#   ./scripts/mobile_screenshots.sh web        — Playwright mobile-viewport on localhost:8088
#   ./scripts/mobile_screenshots.sh all        — run all available platforms
#
# Output: ~/Projects/SOMA/audits/screenshots/mobile/<platform>/<screen>.png
#         ~/Projects/SOMA/audits/screenshots/mobile/contact-sheet.html

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_BASE="$HOME/Projects/SOMA/audits/screenshots/mobile"
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
WEB_URL="${PULSE_URL:-http://localhost:8088}"
ANDROID_PKG="org.esr.sidekick"
ANDROID_ACTIVITY=".MainActivity"

mode="${1:-web}"

# ── helpers ─────────────────────────────────────────────────────────────────

log()  { echo "[mobile-screenshots] $*"; }
fail() { echo "[mobile-screenshots] ERROR: $*" >&2; exit 1; }

mkdir -p "$OUT_BASE/android" "$OUT_BASE/ios" "$OUT_BASE/web-mobile-viewport"

# ── Android mode: ADB screencap ─────────────────────────────────────────────
# Pre-conditions:
#   - adb is on PATH
#   - Device is unlocked and app is installed
#   - USB debugging authorized

capture_android() {
  log "Android: checking adb..."
  which adb >/dev/null 2>&1 || fail "adb not found on PATH"
  local devices
  devices="$(adb devices | grep -v 'List of devices' | grep 'device$' | awk '{print $1}')"
  [[ -z "$devices" ]] && fail "No Android device connected or authorized (is it unlocked?)"
  local device_id
  device_id="$(echo "$devices" | head -1)"
  log "Android device: $device_id"

  # Check app is installed
  adb -s "$device_id" shell pm list packages | grep -q "$ANDROID_PKG" \
    || fail "App $ANDROID_PKG not installed on device"

  # Launch app
  log "Launching $ANDROID_PKG..."
  adb -s "$device_id" shell am start -n "$ANDROID_PKG/$ANDROID_ACTIVITY" >/dev/null
  sleep 4

  # ── Home screen ─────────────────────────────────────────────────────────
  _adb_shot "$device_id" "$OUT_BASE/android/01-home.png"
  log "  screenshot: 01-home"

  # ── Navigate to Routines (checklist icon, top-right AppBar) ─────────────
  # Get UI tree to find button bounds
  _adb_tap_by_desc "$device_id" "Routines" && sleep 2 \
    && _adb_shot "$device_id" "$OUT_BASE/android/03-routines.png" \
    && log "  screenshot: 03-routines" \
    && adb -s "$device_id" shell input keyevent KEYCODE_BACK \
    && sleep 1 || log "  WARN: Routines button not found"

  # ── Navigate to Settings ─────────────────────────────────────────────────
  _adb_tap_by_desc "$device_id" "Settings" && sleep 2 \
    && _adb_shot "$device_id" "$OUT_BASE/android/02-settings.png" \
    && log "  screenshot: 02-settings" \
    && adb -s "$device_id" shell input keyevent KEYCODE_BACK \
    && sleep 1 || log "  WARN: Settings button not found"

  # ── Diagnostics dialog ───────────────────────────────────────────────────
  _adb_tap_by_desc "$device_id" "Diagnostics" && sleep 2 \
    && _adb_shot "$device_id" "$OUT_BASE/android/04-diagnostics.png" \
    && log "  screenshot: 04-diagnostics" \
    && adb -s "$device_id" shell input keyevent KEYCODE_BACK \
    && sleep 1 || log "  WARN: Diagnostics button not found"

  log "Android done. Screenshots in $OUT_BASE/android/"
}

_adb_shot() {
  local dev="$1" out="$2"
  adb -s "$dev" exec-out screencap -p > "$out"
}

_adb_tap_by_desc() {
  local dev="$1" desc="$2"
  adb -s "$dev" shell uiautomator dump /sdcard/_ui_dump.xml >/dev/null 2>&1
  local xml
  xml="$(adb -s "$dev" shell cat /sdcard/_ui_dump.xml)"
  # Extract bounds for matching content-desc
  local bounds
  bounds="$(echo "$xml" | python3 -c "
import sys, re
xml = sys.stdin.read()
# Find node with content-desc matching
pattern = r'content-desc=\"[^\"]*$1[^\"]*\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"'
m = re.search(pattern.replace('\$1', sys.argv[1]), xml)
if m:
    x = (int(m.group(1)) + int(m.group(3))) // 2
    y = (int(m.group(2)) + int(m.group(4))) // 2
    print(f'{x} {y}')
" "$desc" 2>/dev/null)"
  if [[ -n "$bounds" ]]; then
    local x y
    x="$(echo "$bounds" | awk '{print $1}')"
    y="$(echo "$bounds" | awk '{print $2}')"
    adb -s "$dev" shell input tap "$x" "$y"
    return 0
  fi
  return 1
}

# ── iOS mode: flutter drive ──────────────────────────────────────────────────
# Pre-conditions:
#   - CocoaPods installed
#   - Real iPhone unlocked and trusted, OR iOS Simulator booted
#   - Code-sign cert configured (for real device)

capture_ios() {
  log "iOS: checking flutter drive prerequisites..."
  which pod >/dev/null 2>&1 || { log "BLOCKED: CocoaPods not installed. Run: gem install cocoapods"; return 1; }

  local ios_device
  ios_device="$(flutter devices 2>/dev/null | grep -E 'ios|iPhone' | head -1 | awk -F'•' '{print $2}' | tr -d ' ')"
  [[ -z "$ios_device" ]] && { log "BLOCKED: No iOS device/simulator found"; return 1; }
  log "iOS device: $ios_device"

  cd "$PROJECT_ROOT"
  mkdir -p build/test_screenshots/ios
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/screens.dart \
    -d "$ios_device" \
    2>&1 | tee /tmp/flutter_drive_ios.log

  cp build/test_screenshots/ios/*.png "$OUT_BASE/ios/" 2>/dev/null || true
  log "iOS done. Screenshots in $OUT_BASE/ios/"
}

# ── Web mode: Playwright mobile-viewport ─────────────────────────────────────
# Uses the existing Playwright setup in test_e2e/ to navigate the web app
# and capture each tab in iPhone + Pixel viewport.

capture_web() {
  log "Web: capturing Pulse web UI in mobile viewports..."
  curl -s --max-time 3 "$WEB_URL" >/dev/null 2>&1 \
    || fail "Pulse web app not reachable at $WEB_URL. Start it first: flutter run -d web-server --web-port=8088"

  cd "$PROJECT_ROOT"
  node scripts/playwright_mobile_screenshots.js "$OUT_BASE/web-mobile-viewport" "$WEB_URL" 2>&1
  log "Web done. Screenshots in $OUT_BASE/web-mobile-viewport/"
}

# ── Contact sheet ────────────────────────────────────────────────────────────
build_contact_sheet() {
  log "Building contact sheet..."
  node scripts/build_contact_sheet.js "$OUT_BASE" "$TIMESTAMP" 2>&1 \
    && log "Contact sheet: $OUT_BASE/contact-sheet.html"
}

# ── Main ─────────────────────────────────────────────────────────────────────
case "$mode" in
  android) capture_android ;;
  ios)     capture_ios ;;
  web)     capture_web && build_contact_sheet ;;
  all)
    capture_android || log "Android: skipped (see above)"
    capture_ios     || log "iOS: skipped (see above)"
    capture_web
    build_contact_sheet
    ;;
  contact-sheet) build_contact_sheet ;;
  *)
    echo "Usage: $0 [android|ios|web|all|contact-sheet]"
    exit 1
    ;;
esac
