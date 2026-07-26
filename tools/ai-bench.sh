#!/usr/bin/env bash
#
# tools/ai-bench.sh — battery/thermal/memory benchmark harness for the Pulse
# on-device AI chat (ML Kit GenAI Prompt API / Gemini Nano via AICore).
#
# DO NOT RUN THIS while the device is in active use by a human — it drives
# real inference in a loop and will visibly spin up the CPU/NPU. This script
# refuses to run at all if no device is attached.
#
# What it does, in order:
#   1. Aborts if adb isn't on PATH, no device is attached, or more than one
#      device is attached (ambiguous target).
#   2. `adb shell dumpsys battery unplug` + `dumpsys batterystats --reset` so
#      this run's stats aren't polluted by prior history.
#   3. Fires a scripted prompt loop via the debug-only AI_BENCH_RUN broadcast
#      (see android/app/src/main/kotlin/org/esr/sidekick/AiBenchReceiver.kt),
#      which drives GenaiInferenceClient directly — no UI tapping needed.
#   4. Polls `dumpsys meminfo` for the app's PSS while the run is in flight
#      to find a peak, watching logcat for the receiver's completion line.
#   5. Collects `dumpsys batterystats --charged`, `dumpsys thermalservice`,
#      and a final `dumpsys meminfo` snapshot.
#   6. Writes a markdown report.
#   7. Restores battery state (`dumpsys battery reset`) — always, even on
#      early exit, via a trap.
#
# Usage:
#   tools/ai-bench.sh [--prompts "a|b|c"] [--repeat N] [--out PATH] [--max-wait SECONDS]
#
# Requires: the release APK already installed on the attached device
# (org.esr.sidekick) — this script does not build or install anything.

set -euo pipefail

PKG="org.esr.sidekick"
ACTION="org.esr.sidekick.AI_BENCH_RUN"
PROMPTS="What time zone am I probably in right now?|Summarize the point of a morning routine checklist in one sentence.|Give me a 5-word encouraging note for a busy day."
REPEAT=3
OUT=""
POLL_INTERVAL=2
MAX_WAIT_SECONDS=600

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompts) PROMPTS="$2"; shift 2 ;;
    --repeat) REPEAT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --max-wait) MAX_WAIT_SECONDS="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v adb >/dev/null 2>&1; then
  echo "ai-bench: adb not found on PATH. Aborting." >&2
  exit 1
fi

DEVICES="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
if [[ -z "$DEVICES" ]]; then
  echo "ai-bench: no device attached (adb devices shows none in 'device' state). Refusing to run." >&2
  exit 1
fi
DEVICE_COUNT="$(echo "$DEVICES" | wc -l | tr -d ' ')"
if [[ "$DEVICE_COUNT" -gt 1 ]]; then
  echo "ai-bench: multiple devices attached; set ANDROID_SERIAL to disambiguate. Refusing to guess." >&2
  exit 1
fi

echo "ai-bench: checking $PKG is installed on the attached device..."
if ! adb shell pm path "$PKG" >/dev/null 2>&1; then
  echo "ai-bench: $PKG is not installed on the attached device. Install it first (see README)." >&2
  exit 1
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS_SLUG="$(date -u +%Y-%m-%d-%H%M%S)"
if [[ -z "$OUT" ]]; then
  mkdir -p "$REPO_ROOT/tools/ai-bench-reports"
  OUT="$REPO_ROOT/tools/ai-bench-reports/ai-bench-${TS_SLUG}.md"
fi

# Always try to restore battery state, even if we exit early or something fails.
cleanup() {
  echo "ai-bench: restoring battery state (dumpsys battery reset)"
  adb shell dumpsys battery reset >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "ai-bench: unplugging battery + resetting batterystats"
adb shell dumpsys battery unplug
adb shell dumpsys batterystats --reset >/dev/null

echo "ai-bench: clearing logcat"
adb logcat -c

PROMPT_COUNT="$(echo "$PROMPTS" | tr '|' '\n' | grep -c . || true)"
echo "ai-bench: firing broadcast — $PROMPT_COUNT prompt(s) x $REPEAT round(s)"
adb shell am broadcast -a "$ACTION" -p "$PKG" --es prompts "$PROMPTS" --ei repeat "$REPEAT"

echo "ai-bench: polling meminfo for peak PSS while the run is in flight (max ${MAX_WAIT_SECONDS}s)"
PEAK_PSS_KB=0
START_EPOCH=$(date +%s)
DONE=0
TIMED_OUT=0
while [[ $DONE -eq 0 ]]; do
  NOW=$(date +%s)
  if (( NOW - START_EPOCH > MAX_WAIT_SECONDS )); then
    echo "ai-bench: timed out waiting for 'ai-bench: loop complete' in logcat after ${MAX_WAIT_SECONDS}s" >&2
    TIMED_OUT=1
    break
  fi
  SAMPLE_PSS="$(adb shell dumpsys meminfo "$PKG" 2>/dev/null | grep -E "TOTAL PSS|^ *TOTAL " | head -1 | grep -oE "[0-9]+" | head -1 || true)"
  if [[ -n "${SAMPLE_PSS:-}" ]] && (( SAMPLE_PSS > PEAK_PSS_KB )); then
    PEAK_PSS_KB=$SAMPLE_PSS
  fi
  if adb logcat -d -s AiBenchReceiver:I 2>/dev/null | grep -q "ai-bench: loop complete"; then
    DONE=1
  else
    sleep "$POLL_INTERVAL"
  fi
done

echo "ai-bench: collecting final dumps"
BATTERYSTATS="$(adb shell dumpsys batterystats --charged "$PKG" 2>/dev/null || true)"
THERMAL="$(adb shell dumpsys thermalservice 2>/dev/null || true)"
MEMINFO="$(adb shell dumpsys meminfo "$PKG" 2>/dev/null || true)"
LOGCAT_TAIL="$(adb logcat -d -s AiBenchReceiver:I 2>/dev/null || true)"

MODELED_POWER="$(echo "$BATTERYSTATS" | grep -A 5 -i "Estimated power use" || true)"
THERMAL_STATUS="$(echo "$THERMAL" | grep -iE "status|throttl" | head -20 || true)"

cat > "$OUT" <<EOF
# ai-bench report — $TS

- Package: \`$PKG\`
- Prompts per round: $PROMPT_COUNT
- Rounds: $REPEAT
- Peak PSS observed during run: ${PEAK_PSS_KB} kB
- Timed out waiting for completion: $([ "$TIMED_OUT" -eq 1 ] && echo "YES — see raw batterystats/thermal below, they may reflect a partial run" || echo "no")

## Modeled power use (\`dumpsys batterystats --charged $PKG\`, "Estimated power use" section)

\`\`\`
${MODELED_POWER:-"(not found — see full batterystats dump below)"}
\`\`\`

## Thermal status (\`dumpsys thermalservice\`)

\`\`\`
${THERMAL_STATUS:-"(no status/throttl lines matched — see full dump below)"}
\`\`\`

## ai-bench run log (logcat, tag AiBenchReceiver)

\`\`\`
${LOGCAT_TAIL:-"(no log lines captured)"}
\`\`\`

## Full raw dumps

<details><summary>dumpsys batterystats --charged $PKG</summary>

\`\`\`
$BATTERYSTATS
\`\`\`
</details>

<details><summary>dumpsys thermalservice</summary>

\`\`\`
$THERMAL
\`\`\`
</details>

<details><summary>dumpsys meminfo $PKG (final snapshot)</summary>

\`\`\`
$MEMINFO
\`\`\`
</details>
EOF

echo "ai-bench: report written to $OUT"
