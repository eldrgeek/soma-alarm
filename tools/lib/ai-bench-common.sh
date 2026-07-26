#!/usr/bin/env bash
# tools/lib/ai-bench-common.sh — shared helpers for tools/ai-bench.sh and
# tools/gemma-interview.sh. Not standalone-executable; `source` it.
#
# Both scripts drive the debug-only AI_BENCH_RUN broadcast receiver
# (AiBenchReceiver.kt) via `adb shell am broadcast`. Two hard-won lessons
# from the 2026-07-26 interview attempt are encoded here so neither script
# can regress them:
#
#   1. Shell-quoting corruption. A scripted `adb shell am broadcast ... --es
#      prompts 'multi word'` gets re-tokenized by the LOCAL shell before adb
#      ever sees it, corrupting the intent (one observed failure: a stray
#      token bled into an unrelated `pkg=` field). Fix: build the ENTIRE
#      remote command as a single string and hand it to `adb shell "..."` as
#      one argument, with internal single-quotes for the DEVICE's shell to
#      tokenize.
#
#   2. Frozen/cached-process delivery gap. `am broadcast` reporting
#      "Broadcast completed: result=0" is NOT proof of delivery to a
#      cached/frozen app process — the manifest receiver can simply never
#      run, silently, even 3+ minutes later (`bcast_delay_cached_millis`
#      stayed live the whole time in the observed failure). `-f 0x10000000`
#      (Intent.FLAG_RECEIVER_FOREGROUND) fixes this at the source. The
#      receiver's own synchronous "ai-bench: starting" log line is the only
#      trustworthy canary that delivery actually happened — always wait for
#      it before trusting anything else about the run.

# remote_quote STRING — produce a single-quoted token safe to embed in a
# command string that will be tokenized by the device's POSIX shell.
# Escapes any embedded single quotes using the standard '\'' trick.
remote_quote() {
  local s=$1
  printf "'%s'" "${s//\'/\'\\\'\'}"
}

# ai_bench_broadcast PKG ACTION PROMPTS REPEAT — fire the AI_BENCH_RUN
# broadcast as a single quoted remote command, with FLAG_RECEIVER_FOREGROUND
# baked in so it bypasses the cached-process delivery delay. PROMPTS is the
# already `|`-joined prompt string (or a single prompt); REPEAT is an int.
ai_bench_broadcast() {
  local pkg="$1" action="$2" prompts="$3" repeat="$4"
  local q_prompts
  q_prompts="$(remote_quote "$prompts")"
  local cmd="am broadcast -a $action -p $pkg -f 0x10000000 --es prompts $q_prompts --ei repeat $repeat"
  echo "ai-bench: firing: adb shell \"$cmd\"" >&2
  adb shell "$cmd"
}

# wait_for_canary TIMEOUT_SECONDS — block until AiBenchReceiver's synchronous
# "ai-bench: starting" log line appears in logcat, or TIMEOUT_SECONDS
# elapses. Returns 0 if seen, 1 on timeout. Caller is responsible for failing
# loudly (with remediation text — see canary_failure_message) on timeout.
wait_for_canary() {
  local timeout_s="$1"
  local start now
  start=$(date +%s)
  while :; do
    if adb logcat -d -s AiBenchReceiver:I 2>/dev/null | grep -q "ai-bench: starting"; then
      return 0
    fi
    now=$(date +%s)
    if (( now - start > timeout_s )); then
      return 1
    fi
    sleep 1
  done
}

# canary_failure_message PKG — standard remediation text, so both scripts
# fail with the same explanation and the same fix.
canary_failure_message() {
  local pkg="$1"
  cat <<MSG
ai-bench: FAILED — 'am broadcast' returned but AiBenchReceiver's synchronous
  "ai-bench: starting" log line never appeared. Broadcast completion is NOT
  proof of delivery to a cached/frozen app process (observed 2026-07-26:
  bcast_delay_cached_millis stayed live 3+ minutes with zero delivery, even
  though 'am broadcast' reported result=0).
  -f 0x10000000 (FLAG_RECEIVER_FOREGROUND) is already applied to this
  broadcast. If this keeps happening, force a cold start first:
    adb shell am kill $pkg
  then re-run.
MSG
}
