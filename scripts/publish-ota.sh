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

cat > "$OTA_DIR/latest.json" << EOF
{
  "version": "$VERSION",
  "version_name": "$VERSION_NAME",
  "build_number": $BUILD_NUMBER,
  "commit": "$COMMIT",
  "built_at": "$BUILT_AT",
  "size": $SIZE,
  "sha256": "$SHA",
  "url": "/pulse.apk",
  "release_notes": "$ROUND_NOTES"
}
EOF
echo "==> Wrote $OTA_DIR/latest.json"

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
