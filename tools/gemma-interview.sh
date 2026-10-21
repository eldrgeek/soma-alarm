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
# FOREGROUND RULE (rewritten 2026-08-10 — the previous version of this comment
# described the exact OPPOSITE behaviour and was wrong): before every probe this
# requires the device to be UNLOCKED and brings org.esr.sidekick to the
# FOREGROUND, because ML Kit GenAI / AICore refuses inference for a backgrounded
# app (ErrorCode 30, BACKGROUND_USE_BLOCKED). This tool is therefore NOT headless
# — it takes over the screen while it runs. Do not run it on a phone someone is
# using. The old rule aborted *if* the app was foregrounded, which guaranteed
# every probe failed.
#
# A NOTE ON COMMENTS IN THIS TOOL: the receiver hook was unreachable from adb for
# two weeks because a manifest comment asserted "exported=false; adb shell can
# still reach it", which is false. Two commits then "hardened" delivery against a
# bug that did not exist. If you change behaviour here, change the prose in the
# same commit — a confident wrong comment costs more than no comment.
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
# 90s was the original default and it is too short for any realistic prompt.
# Measured 2026-08-10 on a Pixel 10 Pro XL (first run where probes actually
# executed): the short self-description probe returned in 6.4s / 309 chars, but
# BOTH probes carrying a realistic ~1-2k-token working set (board narration,
# intent routing) blew past 90s and were recorded as timeouts. Raised to 300s so
# a timeout means "too slow to be usable" rather than "we stopped watching".
# The latency itself is the finding — see the run notes; do not tune this down
# to make the report look greener.
PROBE_TIMEOUT_SECONDS=300
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

# check_foreground_safe — INVERTED 2026-08-10. This used to abort if
# org.esr.sidekick was the FOREGROUND app, on the theory that the broadcast hook
# is headless and must never contend with a live human session. That theory is
# incompatible with the platform: ML Kit GenAI / AICore refuses inference for a
# backgrounded app —
#
#   GenAiException [ErrorCode 30]: Background usage is blocked. Please use the
#   API when your app is in the foreground instead.
#   (AICore error type 2-INFERENCE_ERROR, code 30-BACKGROUND_USE_BLOCKED)
#
# so the old rule guaranteed every probe failed even once broadcast delivery was
# fixed. The requirement is the exact opposite: the device must be UNLOCKED and
# Pulse must be FOREGROUNDED. Both are checked here and the second is done for
# you; only the unlock is left to a human, because it needs a fingerprint.
check_foreground_safe() {
  local locked focus
  locked="$(adb shell dumpsys window 2>/dev/null | grep -m1 mDreamingLockscreen || true)"
  if echo "$locked" | grep -q "mDreamingLockscreen=true"; then
    echo "" >&2
    echo "gemma-interview: ABORTING — the device is LOCKED." >&2
    echo "  AICore will not run inference for a backgrounded app, and nothing can" >&2
    echo "  take foreground behind a lockscreen. Unlock the phone and re-run." >&2
    echo "  This is the one step that genuinely needs a human fingertip." >&2
    exit 1
  fi

  focus="$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)"
  if ! echo "$focus" | grep -q "$PKG"; then
    echo "gemma-interview: foregrounding $PKG (AICore requires it)..."
    adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    sleep 5
    focus="$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)"
    if ! echo "$focus" | grep -q "$PKG"; then
      echo "" >&2
      echo "gemma-interview: ABORTING — could not bring $PKG to the foreground:" >&2
      echo "  $focus" >&2
      exit 1
    fi
  fi
}

# fetch_long_log — full logcat entries for our tag, in `-v long` format.
# Essential (not just default/brief format) because a chunk of Gemma's
# response can itself contain embedded newlines (e.g. a list); `-v long`
# delimits each log ENTRY with a `[ ... ]` header line so multi-line
# messages can be told apart from the next entry, instead of silently
# truncating at the first physical line.
fetch_long_log() {
  # NOTE 2026-08-10: this used to pass TWO filterspecs (`-s AiBenchReceiver:I
  # AiBenchReceiver:E`), which silently returns ZERO lines — measured 0 vs 211
  # for a plain grep over the same buffer. logcat priorities are "this level and
  # ABOVE", so `:I` already covers W/E/F and the second spec was redundant as
  # well as fatal. This broke response reassembly; the completion poll below had
  # the identical bug, which is why every probe in every run was recorded as a
  # timeout even when inference had finished in ~6s. The canary check in
  # tools/lib/ai-bench-common.sh always used the single-spec form, which is
  # exactly why canaries were detected and nothing else ever was.
  adb logcat -d -v long -s AiBenchReceiver:I 2>/dev/null || true
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

# write_report — installed as an EXIT trap below so a run that dies partway
# through still persists whatever it managed to collect.
#
# 2026-08-10: this used to be a bare block at the end of the script. Probe 8 hit
# BACKGROUND_USE_BLOCKED, the run died there, and the report was never written —
# which silently discarded the response TEXT of all SEVEN probes that had already
# PASSED. Their latencies survived only because they were echoed to stdout as
# they happened. A partial report is strictly better than no report; a run that
# collected real data must never exit without writing it down.
REPORT_WRITTEN=0
write_report() {
  [[ "$REPORT_WRITTEN" -eq 1 ]] && return 0
  REPORT_WRITTEN=1
  [[ "${#REPORT_ENTRIES[@]}" -eq 0 ]] && return 0
{
  echo "# Gemma capability interview — $TS"
  echo ""
  echo "- Package: \`$PKG\`"
  echo "- Probes file: \`$PROBES_FILE\`"
  echo "- Total probes: $TOTAL"
  echo "- Passed: $PASS_COUNT"
  echo "- Failed / timed out: $FAIL_COUNT"
  if [[ $((PASS_COUNT + FAIL_COUNT)) -lt $TOTAL ]]; then
    echo "- **INCOMPLETE RUN** — only $((PASS_COUNT + FAIL_COUNT)) of $TOTAL probes ran before the run ended."
  fi
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
}


# Install BEFORE the probe loop so a mid-loop death still persists results.
trap write_report EXIT

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
    # Single filterspec only — see the note in fetch_long_log above. The
    # two-spec form returns nothing and turns every finished probe into a
    # "timeout".
    BRIEF="$(adb logcat -d -s AiBenchReceiver:I 2>/dev/null || true)"
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

  # `|| true` on every extraction below is load-bearing under `set -euo pipefail`:
  # these helpers are grep/awk pipelines, and a NO-MATCH exits 1, which under
  # `set -e` kills the entire run mid-probe rather than recording one bad probe
  # and moving on. Observed 2026-08-10: probe 8 hit BACKGROUND_USE_BLOCKED and
  # the script died there, losing probes 9-11 AND the report — which is where the
  # response text for all seven PASSING probes lived. One failed probe must never
  # be able to discard the whole run's results.
  JOINED="$(fetch_long_log | join_long_entries || true)"

  if [[ "$ERRORED" -eq 1 ]]; then
    ERR_LINE="$(extract_error_line "$JOINED" || true)"
    echo "gemma-interview: [$N/$TOTAL] INFERENCE ERROR — $ERR_LINE" >&2
    REPORT_ENTRIES+=("### Probe $N — INFERENCE ERROR

> ${PROBE}

\`${ERR_LINE:-"(error line not found — see raw logcat)"}\`")
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  META_LINE="$(extract_meta_line "$JOINED" || true)"
  LATENCY_MS="$(echo "$META_LINE" | grep -oE '[0-9]+ms' | head -1 | tr -d 'ms' || true)"
  CHARS="$(echo "$META_LINE" | grep -oE '[0-9]+ chars' | head -1 | grep -oE '[0-9]+' || true)"
  RESPONSE_TEXT="$(extract_response_text "$JOINED" || true)"

  echo "gemma-interview: [$N/$TOTAL] OK — ${LATENCY_MS:-?}ms, ${CHARS:-?} chars"
  PASS_COUNT=$((PASS_COUNT + 1))
  REPORT_ENTRIES+=("### Probe $N — OK (${LATENCY_MS:-unknown}ms, ${CHARS:-unknown} chars)

> ${PROBE}

**Response:**

${RESPONSE_TEXT:-"(empty response)"}")
done

write_report
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
