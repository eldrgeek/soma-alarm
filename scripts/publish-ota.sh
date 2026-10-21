#!/usr/bin/env bash
# publish-ota.sh — build release APK and publish to ~/.pulse-ota/ OTA server.
# Run manually after meaningful builds. Does NOT auto-run on commit.
#
# Usage: scripts/publish-ota.sh [--skip-build]
#   --skip-build  Skip flutter build (use existing app-release.apk)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OTA_DIR="$HOME/.pulse-ota"
APK_SRC="$REPO_ROOT/build/app/outputs/flutter-apk/app-release.apk"
APK_DEST="$OTA_DIR/pulse.apk"

SKIP_BUILD=false
RUN_TESTS=false
TEST_BACKEND="all"
for arg in "$@"; do
  [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=true
  [[ "$arg" == "--test" ]] && RUN_TESTS=true
  [[ "$arg" == "--test-backend=android" ]] && TEST_BACKEND="android"
  [[ "$arg" == "--test-backend=web" ]]     && TEST_BACKEND="web"
done

mkdir -p "$OTA_DIR"

if [[ "$SKIP_BUILD" == false ]]; then
  echo "==> Building release APK…"
  cd "$REPO_ROOT"
  GIT_SHA=$(git rev-parse HEAD)
  GIT_SHORT=$(git rev-parse --short HEAD)
  GIT_MSG=$(git log -1 --pretty=%s)
  BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > lib/src/build_info.dart << EOF
// AUTO-GENERATED — do not edit by hand.
// Regenerated during flutter build.

const String kBuildGitShaFull = '$GIT_SHA';
const String kBuildGitShaShort = '$GIT_SHORT';
const String kBuildCommitSubject = '$GIT_MSG';
const String kBuildTime = '$BUILD_TIME';
EOF
  flutter build apk --release
  echo "==> Build done."
else
  echo "==> Skipping build (--skip-build)."
fi

if [[ ! -f "$APK_SRC" ]]; then
  echo "ERROR: APK not found at $APK_SRC" >&2
  exit 1
fi

# Backup previous APK
if [[ -f "$APK_DEST" ]]; then
  TS=$(date +%Y%m%d-%H%M%S)
  cp "$APK_DEST" "$OTA_DIR/pulse.apk.bak-$TS"
  echo "==> Backed up old APK as pulse.apk.bak-$TS"
fi

cp "$APK_SRC" "$APK_DEST"
echo "==> Copied APK to $APK_DEST"

# Compute metadata
SHA=$(shasum -a 256 "$APK_DEST" | awk '{print $1}')
SIZE=$(stat -f%z "$APK_DEST" 2>/dev/null || stat -c%s "$APK_DEST")
cd "$REPO_ROOT"
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME="${VERSION%+*}"
BUILD_NUMBER="${VERSION#*+}"
COMMIT=$(git rev-parse --short HEAD)
BUILT_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ROUND_NOTES=$(grep -A5 'kRoundDescription' lib/src/round_info.dart | grep -v 'kRoundDescription' | sed "s/'''\|;$//" | tr -d "'" | head -3 | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')

echo "==> Version: $VERSION  SHA256: $SHA  Size: $SIZE"

# Build the manifest with a real JSON encoder. The release notes come from
# round_info.dart prose and routinely contain double quotes; interpolating them
# straight into a heredoc produced invalid JSON, which made OtaService's
# jsonDecode throw and silently killed the in-app update check.
ROUND_NOTES="$ROUND_NOTES" VERSION="$VERSION" VERSION_NAME="$VERSION_NAME" \
BUILD_NUMBER="$BUILD_NUMBER" COMMIT="$COMMIT" BUILT_AT="$BUILT_AT" \
SIZE="$SIZE" SHA="$SHA" python3 -c '
import json, os
m = {
    "version":       os.environ["VERSION"],
    "version_name":  os.environ["VERSION_NAME"],
    "build_number":  int(os.environ["BUILD_NUMBER"]),
    "commit":        os.environ["COMMIT"],
    "built_at":      os.environ["BUILT_AT"],
    "size":          int(os.environ["SIZE"]),
    "sha256":        os.environ["SHA"],
    "url":           "/pulse.apk",
    "release_notes": os.environ["ROUND_NOTES"],
}
print(json.dumps(m, indent=2))
' > "$OTA_DIR/latest.json"

# Fail loudly rather than publishing a manifest the app cannot parse.
python3 -m json.tool "$OTA_DIR/latest.json" > /dev/null \
  || { echo "ERROR: generated latest.json is not valid JSON" >&2; exit 1; }
echo "==> Wrote $OTA_DIR/latest.json (validated)"

cat > "$OTA_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pulse OTA — v$VERSION</title>
  <style>
    body { font-family: monospace; padding: 2rem; background: #111; color: #eee; }
    h1 { color: #f90; }
    .meta { color: #aaa; font-size: 0.85rem; margin: 0.4rem 0; }
    a.dl { display: inline-block; margin-top: 1.5rem; padding: 0.6rem 1.4rem;
           background: #f90; color: #000; text-decoration: none; border-radius: 4px; font-weight: bold; }
  </style>
</head>
<body>
  <h1>Pulse OTA</h1>
  <div class="meta">Version: $VERSION</div>
  <div class="meta">Build: $BUILD_NUMBER</div>
  <div class="meta">Commit: $COMMIT</div>
  <div class="meta">Built: $BUILT_AT</div>
  <div class="meta">Size: $(( SIZE / 1048576 )) MB</div>
  <div class="meta">SHA-256: $SHA</div>
  <p>$ROUND_NOTES</p>
  <a class="dl" href="pulse.apk">Download APK</a>
</body>
</html>
EOF
echo "==> Wrote $OTA_DIR/index.html"

# ---------------------------------------------------------------------------
# Publish to the VPS. This is the server the app actually reads: commit 2021893
# moved OtaService's _otaBase from the Mac's tailnet address to
# https://vpsmikewolf.duckdns.org/pulse-ota, but this script kept writing only
# to $OTA_DIR on the Mac. Consumer and publisher pointed at different hosts, so
# every in-app update check 404'd. Keep this step in lockstep with _otaBase.
# ---------------------------------------------------------------------------
VPS_HOST="${PULSE_OTA_VPS_HOST:-vps}"
VPS_OTA_DIR="/var/www/pulse-ota"

if [[ "${SKIP_VPS:-false}" == true ]]; then
  echo "==> Skipping VPS publish (SKIP_VPS=true)."
elif ssh -o BatchMode=yes -o ConnectTimeout=15 "$VPS_HOST" true 2>/dev/null; then
  ssh -o BatchMode=yes "$VPS_HOST" "sudo install -d -o ubuntu -g ubuntu -m 755 $VPS_OTA_DIR"
  rsync -a "$OTA_DIR/pulse.apk" "$OTA_DIR/latest.json" "$OTA_DIR/index.html" \
    "$VPS_HOST:$VPS_OTA_DIR/"
  echo "==> Published to $VPS_HOST:$VPS_OTA_DIR"

  # Verify what the phone will actually fetch, not just what we uploaded.
  REMOTE_BUILD=$(curl -fsS --max-time 20 \
    https://vpsmikewolf.duckdns.org/pulse-ota/latest.json | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["build_number"])' 2>/dev/null || echo "")
  if [[ "$REMOTE_BUILD" == "$BUILD_NUMBER" ]]; then
    echo "==> VERIFIED: OTA endpoint serves build $REMOTE_BUILD"
  else
    echo "WARNING: OTA endpoint reports build '$REMOTE_BUILD', expected '$BUILD_NUMBER'" >&2
  fi
else
  echo "WARNING: cannot reach VPS '$VPS_HOST' — phone will NOT see this build." >&2
  echo "         Re-run once connectivity is back, or set SKIP_VPS=true to silence." >&2
fi

echo ""
echo "Done. OTA server should serve the new build immediately."
echo "Device can self-update via About → Install update."

if [[ "$RUN_TESTS" == true ]]; then
  RSI_RUNNER="$HOME/Projects/SOMA/tools/pulse-rsi/run_all.py"
  if [[ ! -f "$RSI_RUNNER" ]]; then
    echo "WARNING: RSI runner not found at $RSI_RUNNER — skipping tests." >&2
  else
    echo ""
    echo "==> Running RSI test suite (--backend $TEST_BACKEND)…"
    python3 "$RSI_RUNNER" --backend "$TEST_BACKEND" --version "$VERSION" || true
  fi
fi
