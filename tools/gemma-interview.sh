#!/usr/bin/env bash
#
# tools/gemma-interview.sh — unattended on-device capability interview for
# Gemma (Gemini Nano via ML Kit GenAI Prompt API), driven through the same
# debug-only AI_BENCH_RUN broadcast hook as tools/ai-bench.sh (see
# android/app/src/main/kotlin/org/esr/sidekick/AiBenchReceiver.kt).
#
# Fires each probe from tools/gemma-probes.txt (one per line, editable
# without touching this script) as its own single-prompt broadcast round,
# waits for the delivery canary + completion, reassembles the full chunked
# response text, records latency, and writes a markdown transcript to
# tools/interview-reports/.
#
# DELIVERY HARDENING (2026-07-26 lesson — see tools/lib/ai-bench-common.sh):
# every broadcast is fired with FLAG_RECEIVER_FOREGROUND as a single quoted
# `adb shell "..."` command, and this script waits for the receiver's own
# synchronous "ai-bench: starting" log line before trusting anything else —
# `am broadcast` reporting "completed" is NOT proof of delivery to a
# cached/frozen app process.
#
# SAFETY RULE: before every probe this checks `dumpsys window | grep
# mCurrentFocus`. If org.esr.sidekick is the foreground app, it ABORTS —
# Mike may be using the chat himself; this tool never contends with a live
# session. Any other foreground app (including the launcher) is fine — this
# drives the app via broadcast, not the UI, so it is headless either way.
#
# Usage:
#   tools/gemma-interview.sh [--probes PATH] [--out PATH] \
#     [--canary-timeout SECONDS] [--probe-timeout SECONDS]
#
# Requires: the release APK already installed on the attached device
# (org.esr.sidekick) — this script does not build or install anything.

set -euo pipefail

PKG="org.esr.sidekick"
ACTION="org.esr.sidekick.AI_BENCH_RUN"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBES_FILE="$SCRIPT_DIR/gemma-probes.txt"
OUT=""
CANARY_TIMEOUT_SECONDS=20
PROBE_TIMEOUT_SECONDS=90
POLL_INTERVAL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probes) PROBES_FILE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --canary-timeout) CANARY_TIMEOUT_SECONDS="$2"; shift 2 ;;
    --probe-timeout) PROBE_TIMEOUT_SECONDS="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# shellcheck source=tools/lib/ai-bench-common.sh
source "$SCRIPT_DIR/lib/ai-bench-common.sh"

if ! command -v adb >/dev/null 2>&1; then
  echo "gemma-interview: adb not found on PATH. Aborting." >&2
  exit 1
fi

DEVICES="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
if [[ -z "$DEVICES" ]]; then
  echo "gemma-interview: no device attached (adb devices shows none in 'device' state). Refusing to run." >&2
  exit 1
fi
DEVICE_COUNT="$(echo "$DEVICES" | wc -l | tr -d ' ')"
if [[ "$DEVICE_COUNT" -gt 1 ]]; then
  echo "gemma-interview: multiple devices attached; set ANDROID_SERIAL to disambiguate. Refusing to guess." >&2
  exit 1
fi

if [[ ! -f "$PROBES_FILE" ]]; then
  echo "gemma-interview: probes file not found: $PROBES_FILE" >&2
  exit 1
fi

echo "gemma-interview: checking $PKG is installed on the attached device..."
if ! adb shell pm path "$PKG" >/dev/null 2>&1; then
  echo "gemma-interview: $PKG is not installed on the attached device. Install it first (see README)." >&2
  exit 1
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS_SLUG="$(date -u +%Y-%m-%d-%H%M%S)"
if [[ -z "$OUT" ]]; then
  mkdir -p "$REPO_ROOT/tools/interview-reports"
  OUT="$REPO_ROOT/tools/interview-reports/gemma-interview-${TS_SLUG}.md"
fi

# Load probes: strip comments (#...) and blank lines, preserve order. Each
# remaining line is one self-contained prompt (the receiver is stateless).
PROBES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  PROBES+=("$line")
done < "$PROBES_FILE"

if [[ "${#PROBES[@]}" -eq 0 ]]; then
  echo "gemma-interview: no probes parsed from $PROBES_FILE" >&2
  exit 1
fi
TOTAL="${#PROBES[@]}"

echo "gemma-interview: growing logcat buffer to 16M so long responses can't be evicted"
adb logcat -G 16M >/dev/null 2>&1 || echo "gemma-interview: warning — could not grow logcat buffer, continuing anyway" >&2

# check_foreground_safe — abort the whole run if org.esr.sidekick is the
# foreground app. Mike may be using the chat himself; never contend with him.
check_foreground_safe() {
  local focus
  focus="$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)"
  if echo "$focus" | grep -q "$PKG"; then
    echo "" >&2
    echo "gemma-interview: ABORTING — $PKG is in the foreground:" >&2
    echo "  $focus" >&2
    echo "  Mike may be using the chat himself right now. This tool never contends" >&2
    echo "  with a live session. Re-run once the app is backgrounded." >&2
    exit 1
  fi
}

# fetch_long_log — full logcat entries for our tag, in `-v long` format.
# Essential (not just default/brief format) because a chunk of Gemma's
# response can itself contain embedded newlines (e.g. a list); `-v long`
# delimits each log ENTRY with a `[ ... ]` header line so multi-line
# messages can be told apart from the next entry, instead of silently
# truncating at the first physical line.
fetch_long_log() {
  adb logcat -d -v long -s AiBenchReceiver:I AiBenchReceiver:E 2>/dev/null || true
}

# join_long_entries — reads `-v long` logcat on stdin, emits ONE line per
# log entry with any internal newline replaced by the literal two-character
# sequence \n, so downstream grep/sort/sed (line-oriented tools) can operate
# safely without truncating a multi-line chunk to its first physical line.
join_long_entries() {
  awk '
    /^\[.*\]$/ {
      if (started) { print msg }
      msg = ""; started = 1; next
    }
    {
      if (!started) { next }
      if (msg == "") { msg = $0 } else { msg = msg "\\n" $0 }
    }
    END { if (started) print msg }
  '
}

# extract_meta_line JOINED_LOG — the "ai-bench: [1/1] {elapsed}ms, {chars}
# chars back for: ..." line for a single-prompt (n=1, total=1) round.
extract_meta_line() {
  echo "$1" | grep -E '^ai-bench: \[1/1\] [0-9]+ms' | head -1
}

# extract_error_line JOINED_LOG — the Log.e failure line, if inference threw.
extract_error_line() {
  echo "$1" | grep -E '^ai-bench: \[1/1\] failed' | head -1
}

# extract_response_text JOINED_LOG — reassembles the full response from
# `ai-bench-text[1][idx/total] chunk` lines: filter by prefix, sort
# numerically by chunk index, strip the prefix, concatenate directly (chunks
# are contiguous substrings — no separator belongs between them), then turn
# the literal \n markers back into real newlines.
#
# Caveat (documented, not fully solved): join_long_entries appends a
# trailing \n artifact per entry (the blank separator line -v long emits
# between entries), stripped per-line below; a chunk boundary that happens
# to land exactly on a real newline in Gemma's text is the one case this
# can't distinguish from that artifact. Rare, and not worth more complexity
# for an internal interview tool.
extract_response_text() {
  local joined="$1"
  echo "$joined" \
    | grep -E '^ai-bench-text\[1\]\[[0-9]+/[0-9]+\] ?' \
    | sed -E 's/^ai-bench-text\[1\]\[([0-9]+)\/[0-9]+\] ?/\1\t/' \
    | sort -t "$(printf '\t')" -k1,1n \
    | sed -E 's/^[0-9]+\t//' \
    | sed 's/\\n$//' \
    | tr -d '\n' \
    | sed 's/\\n/\n/g'
}

REPORT_ENTRIES=()
PASS_COUNT=0
FAIL_COUNT=0

echo "gemma-interview: $TOTAL probe(s) queued from $PROBES_FILE"

for i in "${!PROBES[@]}"; do
  N=$((i + 1))
  PROBE="${PROBES[$i]}"

  echo ""
  echo "gemma-interview: [$N/$TOTAL] safety check (mCurrentFocus)..."
  check_foreground_safe

  echo "gemma-interview: [$N/$TOTAL] clearing logcat"
  adb logcat -c

  echo "gemma-interview: [$N/$TOTAL] firing probe: ${PROBE:0:80}..."
  ai_bench_broadcast "$PKG" "$ACTION" "$PROBE" 1 >/dev/null

  if ! wait_for_canary "$CANARY_TIMEOUT_SECONDS"; then
    canary_failure_message "$PKG" >&2
    REPORT_ENTRIES+=("### Probe $N — DELIVERY FAILED

> ${PROBE}

Broadcast never reached the receiver within ${CANARY_TIMEOUT_SECONDS}s (\"ai-bench: starting\" never appeared). Likely a cached/frozen-process delivery gap that survived \`-f 0x10000000\`; see script stderr for remediation (\`adb shell am kill $PKG\` then retry).")
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi
  echo "gemma-interview: [$N/$TOTAL] canary confirmed, waiting for completion (max ${PROBE_TIMEOUT_SECONDS}s)"

  DONE=0
  ERRORED=0
  START_EPOCH=$(date +%s)
  while [[ $DONE -eq 0 ]]; do
    NOW=$(date +%s)
    if (( NOW - START_EPOCH > PROBE_TIMEOUT_SECONDS )); then
      break
    fi
    BRIEF="$(adb logcat -d -s AiBenchReceiver:I AiBenchReceiver:E 2>/dev/null || true)"
    if echo "$BRIEF" | grep -q "ai-bench: loop complete"; then
      DONE=1
    elif echo "$BRIEF" | grep -q "ai-bench: \[1/1\] failed"; then
      DONE=1
      ERRORED=1
    else
      sleep "$POLL_INTERVAL"
    fi
  done

  if [[ "$DONE" -eq 0 ]]; then
    echo "gemma-interview: [$N/$TOTAL] TIMED OUT waiting for completion after ${PROBE_TIMEOUT_SECONDS}s" >&2
    REPORT_ENTRIES+=("### Probe $N — TIMED OUT

> ${PROBE}

Canary fired but no completion line within ${PROBE_TIMEOUT_SECONDS}s. Inference may be unusually slow for this probe (check the long-context one first) or the process died mid-run.")
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  JOINED="$(fetch_long_log | join_long_entries)"

  if [[ "$ERRORED" -eq 1 ]]; then
    ERR_LINE="$(extract_error_line "$JOINED")"
    echo "gemma-interview: [$N/$TOTAL] INFERENCE ERROR — $ERR_LINE" >&2
    REPORT_ENTRIES+=("### Probe $N — INFERENCE ERROR

> ${PROBE}

\`${ERR_LINE:-"(error line not found — see raw logcat)"}\`")
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  META_LINE="$(extract_meta_line "$JOINED")"
  LATENCY_MS="$(echo "$META_LINE" | grep -oE '[0-9]+ms' | head -1 | tr -d 'ms')"
  CHARS="$(echo "$META_LINE" | grep -oE '[0-9]+ chars' | head -1 | grep -oE '[0-9]+')"
  RESPONSE_TEXT="$(extract_response_text "$JOINED")"

  echo "gemma-interview: [$N/$TOTAL] OK — ${LATENCY_MS:-?}ms, ${CHARS:-?} chars"
  PASS_COUNT=$((PASS_COUNT + 1))
  REPORT_ENTRIES+=("### Probe $N — OK (${LATENCY_MS:-unknown}ms, ${CHARS:-unknown} chars)

> ${PROBE}

**Response:**

${RESPONSE_TEXT:-"(empty response)"}")
done

{
  echo "# Gemma capability interview — $TS"
  echo ""
  echo "- Package: \`$PKG\`"
  echo "- Probes file: \`$PROBES_FILE\`"
  echo "- Total probes: $TOTAL"
  echo "- Passed: $PASS_COUNT"
  echo "- Failed / timed out: $FAIL_COUNT"
  echo ""
  echo "**Multi-turn caveat:** AiBenchReceiver is stateless per broadcast — each probe above is a"
  echo "single, independent prompt. The multi-turn probe simulates prior turns by including them"
  echo "inline as text in the same prompt; it is not a real multi-turn session and cannot surface"
  echo "state-carrying bugs (context truncation across turns, drift, etc.) that a live conversation"
  echo "loop in the chat UI would."
  echo ""
  echo "---"
  echo ""
  for entry in "${REPORT_ENTRIES[@]}"; do
    echo "$entry"
    echo ""
    echo "---"
    echo ""
  done
} > "$OUT"

echo ""
echo "gemma-interview: report written to $OUT ($PASS_COUNT/$TOTAL passed)"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
