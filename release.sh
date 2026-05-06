#!/usr/bin/env bash
# release.sh — build & ship Pulse (sidekick) APKs
# Subcommands: build | push-local | push-vps | push-all | status
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PACKAGE="org.esr.sidekick"
PIXEL_FALLBACK_IP="192.168.4.27:5555"   # last-known wireless adb endpoint
VPS_HOST="vpsmikewolf.duckdns.org"
VPS_USER="dev"
VPS_DEST_DIR="/var/www/pulse"
VPS_URL="https://${VPS_HOST}/pulse/latest.apk"
QR_PNG="${REPO_ROOT}/release/pulse-install-qr.png"
BUILD_DIR="${REPO_ROOT}/build/app/outputs/flutter-apk"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { printf '\033[1;36m▶\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "missing required binary: $bin"
  done
}

ssh_vps() {
  if [[ -n "${VPS_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$VPS_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$@"
  else
    ssh -o ConnectTimeout=5 "$@"
  fi
}
scp_vps() {
  if [[ -n "${VPS_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$VPS_PASSWORD" scp -o StrictHostKeyChecking=no -p "$@"
  else
    scp -p "$@"
  fi
}

# ── Build ─────────────────────────────────────────────────────────────────────
DEBUG=0
FORCE=0
parse_global_flags() {
  REMAINING=()
  for arg in "$@"; do
    case "$arg" in
      --debug) DEBUG=1 ;;
      --force) FORCE=1 ;;
      *) REMAINING+=("$arg") ;;
    esac
  done
}

current_apk_path() {
  if [[ "$DEBUG" -eq 1 ]]; then
    echo "${BUILD_DIR}/app-debug.apk"
  else
    echo "${BUILD_DIR}/app-release.apk"
  fi
}

apk_version() {
  local apk="$1" v=""
  if command -v aapt >/dev/null 2>&1; then
    v="$(aapt dump badging "$apk" 2>/dev/null | awk -F"'" '/package:/ {for(i=1;i<=NF;i++) if($i~/versionName/) print $(i+1)}' | head -1)"
  fi
  if [[ -z "$v" ]] && command -v unzip >/dev/null 2>&1; then
    # Fallback: read versionName from AndroidManifest.xml binary via aapt2 if available, else pubspec
    :
  fi
  if [[ -z "$v" && -f "${REPO_ROOT}/pubspec.yaml" ]]; then
    v="$(awk -F': ' '/^version:/ {print $2; exit}' "${REPO_ROOT}/pubspec.yaml" | awk -F'+' '{print $1}')"
    [[ -n "$v" ]] && v="${v}~pubspec"
  fi
  echo "${v:-unknown}"
}

cmd_build() {
  require flutter
  local apk; apk="$(current_apk_path)"
  if [[ "$FORCE" -eq 0 && -f "$apk" ]]; then
    # Rebuild if any .dart or pubspec changed since the apk
    if [[ -z "$(find "$REPO_ROOT/lib" "$REPO_ROOT/pubspec.yaml" -newer "$apk" 2>/dev/null | head -1)" ]]; then
      log "APK is up to date, skipping build (use --force to rebuild): $apk"
      echo "$apk"
      return 0
    fi
  fi
  log "Running flutter build apk ($([[ $DEBUG -eq 1 ]] && echo --debug || echo --release))"
  cd "$REPO_ROOT"
  if [[ "$DEBUG" -eq 1 ]]; then
    flutter build apk --debug
  else
    flutter build apk --release
  fi
  [[ -f "$apk" ]] || die "expected APK not found at $apk"
  ok "built $apk ($(du -h "$apk" | awk '{print $1}'), v$(apk_version "$apk"))"
  echo "$apk"
}

# ── Local wireless adb push ───────────────────────────────────────────────────
discover_pixel() {
  log "Discovering Pixel via mDNS..."
  local line ipport
  # Format: "adb-XXXX-YYYY  _adb-tls-connect._tcp.  192.168.x.y:5555"
  line="$(adb mdns services 2>/dev/null | grep -E '_adb(-tls)?(-connect)?\._tcp' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | head -1 || true)"
  if [[ -n "$line" ]]; then
    ipport="$line"
    ok "mDNS found Pixel at $ipport"
  else
    warn "no Pixel found via mDNS; trying last-known $PIXEL_FALLBACK_IP"
    ipport="$PIXEL_FALLBACK_IP"
  fi
  log "adb connect $ipport"
  if adb connect "$ipport" 2>&1 | grep -qE 'connected|already connected'; then
    echo "$ipport"
    return 0
  fi
  warn "wireless adb connect failed; falling back to USB"
  local usb
  usb="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  if [[ -n "$usb" ]]; then
    ok "using USB device $usb"
    echo "$usb"
    return 0
  fi
  die "no Pixel reachable. Plug in via USB, or pair wireless adb (Settings → Developer options → Wireless debugging)."
}

cmd_push_local() {
  require adb
  local apk; apk="$(cmd_build | tail -1)"
  local serial; serial="$(discover_pixel)"
  log "adb -s $serial install -r $apk"
  if adb -s "$serial" install -r "$apk" 2>&1 | tee /tmp/pulse-adb-install.log | grep -qE '^Success'; then
    ok "installed on $serial"
  else
    die "adb install failed (see /tmp/pulse-adb-install.log)"
  fi
  local installed
  installed="$(adb -s "$serial" shell dumpsys package "$APP_PACKAGE" 2>/dev/null | awk -F= '/versionName=/ {print $2; exit}' | tr -d '\r')"
  ok "installed version on Pixel: ${installed:-unknown}"
  echo "$apk"
}

# ── VPS push ──────────────────────────────────────────────────────────────────
verify_vps_ssh() {
  log "Verifying SSH access to ${VPS_USER}@${VPS_HOST}"
  if ssh_vps -o BatchMode=$([[ -n "${VPS_PASSWORD:-}" ]] && echo no || echo yes) "${VPS_USER}@${VPS_HOST}" 'echo ok' >/dev/null 2>&1; then
    ok "SSH ok"
  else
    die "SSH to ${VPS_USER}@${VPS_HOST} failed. Check VPN/DNS/VPS up; or set VPS_PASSWORD env var to use sshpass."
  fi
}

cmd_push_vps() {
  require ssh scp
  local apk; apk="$(cmd_build | tail -1)"
  verify_vps_ssh
  log "Ensuring ${VPS_DEST_DIR} exists on VPS"
  ssh_vps "${VPS_USER}@${VPS_HOST}" "mkdir -p ${VPS_DEST_DIR}" || die "mkdir on VPS failed"
  log "scp -p $apk → ${VPS_USER}@${VPS_HOST}:${VPS_DEST_DIR}/latest.apk"
  scp_vps "$apk" "${VPS_USER}@${VPS_HOST}:${VPS_DEST_DIR}/latest.apk" >/dev/null \
    || die "scp failed"
  # also keep a versioned copy
  local ver; ver="$(apk_version "$apk")"
  if [[ -n "$ver" && "$ver" != "unknown" ]]; then
    ssh_vps "${VPS_USER}@${VPS_HOST}" "cp ${VPS_DEST_DIR}/latest.apk ${VPS_DEST_DIR}/sidekick-${ver}.apk" || true
  fi
  ok "uploaded → ${VPS_URL}"
  generate_qr
  echo "$VPS_URL"
}

# ── QR code ───────────────────────────────────────────────────────────────────
generate_qr() {
  command -v qrencode >/dev/null 2>&1 || { warn "qrencode not installed; skipping QR (brew install qrencode)"; return; }
  mkdir -p "$(dirname "$QR_PNG")"
  if [[ -f "$QR_PNG" && "$FORCE" -eq 0 ]]; then
    local existing
    existing="$(qrencode --inline -t ANSIUTF8 < /dev/null 2>/dev/null || true)"
    # Cheap check: regen only if missing or zero-size
    if [[ -s "$QR_PNG" ]]; then
      log "QR already present at $QR_PNG (use --force to regenerate)"
      return
    fi
  fi
  log "Generating QR PNG → $QR_PNG"
  qrencode -s 10 -m 4 -o "$QR_PNG" "$VPS_URL"
  ok "QR: $QR_PNG → $VPS_URL"
}

# ── push-all ──────────────────────────────────────────────────────────────────
cmd_push_all() {
  cmd_push_local
  cmd_push_vps
}

# ── status ────────────────────────────────────────────────────────────────────
cmd_status() {
  echo "── Local APK ──"
  for apk in "${BUILD_DIR}/app-release.apk" "${BUILD_DIR}/app-debug.apk"; do
    if [[ -f "$apk" ]]; then
      printf '  %s   v%s   %s   %s\n' "$(basename "$apk")" "$(apk_version "$apk")" "$(du -h "$apk" | awk '{print $1}')" "$(date -r "$apk" '+%Y-%m-%d %H:%M:%S')"
    fi
  done

  echo "── Pixel (installed) ──"
  if command -v adb >/dev/null 2>&1; then
    local serial
    serial="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
    if [[ -z "$serial" ]]; then
      adb connect "$PIXEL_FALLBACK_IP" >/dev/null 2>&1 || true
      serial="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
    fi
    if [[ -n "$serial" ]]; then
      local v; v="$(adb -s "$serial" shell dumpsys package "$APP_PACKAGE" 2>/dev/null | awk -F= '/versionName=/ {print $2; exit}' | tr -d '\r')"
      printf '  %s   %s v%s\n' "$serial" "$APP_PACKAGE" "${v:-not-installed}"
    else
      echo "  (no Pixel reachable)"
    fi
  fi

  echo "── VPS (${VPS_URL}) ──"
  local hdr; hdr="$(curl -sI "$VPS_URL" 2>/dev/null || true)"
  if [[ -n "$hdr" ]] && echo "$hdr" | grep -q '200 OK'; then
    local lm sz
    lm="$(echo "$hdr" | awk -F': ' '/^Last-Modified/ {print $2}' | tr -d '\r')"
    sz="$(echo "$hdr" | awk -F': ' '/^Content-Length/ {print $2}' | tr -d '\r')"
    printf '  size=%s bytes   last-modified=%s\n' "$sz" "$lm"
  else
    echo "  (unreachable or not uploaded)"
  fi

  echo "── QR ──"
  if [[ -f "$QR_PNG" ]]; then echo "  $QR_PNG"; else echo "  (not generated)"; fi
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: release.sh <subcommand> [--debug] [--force]
  build         Build APK (release by default; --debug for debug)
  push-local    Build + wireless adb install on Pixel
  push-vps      Build + scp to VPS at ${VPS_URL}
  push-all      Both
  status        APK / Pixel / VPS / QR report

Env: VPS_PASSWORD=... to authenticate via sshpass instead of an SSH key.
EOF
}

main() {
  [[ $# -ge 1 ]] || { usage; exit 1; }
  local sub="$1"; shift
  parse_global_flags "$@"
  set -- "${REMAINING[@]:-}"
  case "$sub" in
    build)       cmd_build ;;
    push-local)  cmd_push_local ;;
    push-vps)    cmd_push_vps ;;
    push-all)    cmd_push_all ;;
    status)      cmd_status ;;
    -h|--help)   usage ;;
    *)           usage; exit 1 ;;
  esac
}

main "$@"
