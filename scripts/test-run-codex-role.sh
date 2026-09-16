#!/usr/bin/env bash
# Tests for scripts/run-codex-role.sh using tests/acceptance/mock-companion.mjs.
# Pure bash + node; no real Codex call.

# Assertions are passed to check() as single-quoted strings and expanded by eval there,
# and the variables they read (RC, OUT, FIRST_RC, CLAIM_*) look unused to shellcheck.
# shellcheck disable=SC2016,SC2034

set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$SCRIPT_DIR/run-codex-role.sh"
MOCK="$REPO_ROOT/tests/acceptance/mock-companion.mjs"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else ng "$1"; fi; }

TARGET="$TEST_DIR/target-repo"
mkdir -p "$TARGET"
PROMPT="$TEST_DIR/prompt.md"
printf '<!-- agent-dialectics-role: test/role -->\nhello codex\n' > "$PROMPT"

N=0
# Sets OUT to a fresh attempt directory (no subshell, so N persists).
new_out() { N=$((N + 1)); OUT="$TEST_DIR/out-$N"; }

# Isolated HOME so the real installed_plugins.json / plugin cache are never used.
FAKE_HOME="$TEST_DIR/home"
mkdir -p "$FAKE_HOME"

# run [KEY=VALUE...] <out-dir> [extra args...]  — sets RC.
run() {
  local envs=()
  while [ $# -gt 0 ] && [[ "$1" =~ ^[A-Z_]+= ]]; do
    envs+=("$1"); shift
  done
  local out="$1"; shift
  RC=0
  env HOME="$FAKE_HOME" "${envs[@]}" "$RUNNER" --prompt-file "$PROMPT" --cwd "$TARGET" --out-dir "$out" "$@" \
    >"$TEST_DIR/last-stdout" 2>"$TEST_DIR/last-stderr" || RC=$?
}
RC=0

state_of() { node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).state)' "$1/status.json"; }

echo "== companion resolution =="

# installed_plugins.json array → scope=user installPath
PLUG="$TEST_DIR/plugins-user"
mkdir -p "$PLUG/0.9.0/scripts" "$PLUG/1.0.6/scripts"
cp "$MOCK" "$PLUG/1.0.6/scripts/codex-companion.mjs"
# The project-scope entry is listed first and always fails, so picking entries[0] would not exit 0.
printf 'process.exit(99)\n' > "$PLUG/0.9.0/scripts/codex-companion.mjs"
cat > "$TEST_DIR/installed.json" <<EOF
{"version": 2, "plugins": {"codex@openai-codex": [
  {"scope": "project", "installPath": "$PLUG/0.9.0", "version": "0.9.0"},
  {"scope": "user", "installPath": "$PLUG/1.0.6", "version": "1.0.6"}
]}}
EOF
new_out; LOG="$TEST_DIR/args-user.log"
run INSTALLED_PLUGINS_JSON="$TEST_DIR/installed.json" CODEX_COMPANION_NO_CACHE_FALLBACK=1 MOCK_ARGS_LOG="$LOG" "$OUT"
check "installPath (scope=user) resolved → exit 0" '[ "$RC" -eq 0 ]'
check "  the user-scope companion (not entries[0]) was invoked" '[ -s "$LOG" ]'

# scope=user absent → first entry
cat > "$TEST_DIR/installed-first.json" <<EOF
{"version": 2, "plugins": {"codex@openai-codex": [
  {"scope": "project", "installPath": "$PLUG/1.0.6", "version": "1.0.6"},
  {"scope": "local", "installPath": "$PLUG/0.9.0", "version": "0.9.0"}
]}}
EOF
new_out
run INSTALLED_PLUGINS_JSON="$TEST_DIR/installed-first.json" CODEX_COMPANION_NO_CACHE_FALLBACK=1 "$OUT"
check "no scope=user entry → first entry used → exit 0" '[ "$RC" -eq 0 ]'

# semver fallback from plugin cache
CACHE="$FAKE_HOME/.claude/plugins/cache/openai-codex/codex"
mkdir -p "$CACHE/1.0.10/scripts" "$CACHE/1.0.9/scripts" "$CACHE/not-a-version/scripts"
printf 'process.exit(99)\n' > "$CACHE/1.0.9/scripts/codex-companion.mjs"
printf 'process.exit(99)\n' > "$CACHE/not-a-version/scripts/codex-companion.mjs"
cp "$MOCK" "$CACHE/1.0.10/scripts/codex-companion.mjs"
new_out
run INSTALLED_PLUGINS_JSON="$TEST_DIR/missing.json" "$OUT"
check "cache fallback picks highest semver (1.0.10 > 1.0.9) → exit 0" '[ "$RC" -eq 0 ]'

new_out
run INSTALLED_PLUGINS_JSON="$TEST_DIR/missing.json" CODEX_COMPANION_NO_CACHE_FALLBACK=1 "$OUT"
check "fallback disabled and nothing installed → exit 2" '[ "$RC" -eq 2 ]'
check "exit 2 writes error.log and no answer.md" '[ -f "$OUT/error.log" ] && [ ! -e "$OUT/answer.md" ]'

new_out
run CODEX_COMPANION_PATH=/nonexistent CODEX_COMPANION_NO_CACHE_FALLBACK=1 "$OUT"
check "CODEX_COMPANION_PATH=/nonexistent → exit 2" '[ "$RC" -eq 2 ]'

echo "== setup preflight =="
for case_json in \
  '{"ready":false,"codex":{"available":true},"auth":{"loggedIn":true}}' \
  '{"ready":true,"codex":{"available":false},"auth":{"loggedIn":true}}' \
  '{"ready":true,"codex":{"available":true},"auth":{"loggedIn":false}}'; do
  new_out; LOG="$TEST_DIR/args-setup-$N.log"
  run CODEX_COMPANION_PATH="$MOCK" MOCK_SETUP_JSON="$case_json" MOCK_ARGS_LOG="$LOG" "$OUT"
  check "setup $case_json → exit 2" '[ "$RC" -eq 2 ]'
  check "  task is not invoked when setup is not ready" '! grep -q "\"task\"" "$LOG"'
done
new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_SETUP_EXIT=1 "$OUT"
check "setup exits non-zero → exit 2" '[ "$RC" -eq 2 ]'

echo "== task result classification =="
new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_TASK_EXIT=1 MOCK_STATUS=1 MOCK_RAW_OUTPUT="" \
  MOCK_STDERR="You've hit your usage limit. Try again at 2:50 AM." "$OUT"
check "usage-limit turn failure (non-zero exit) → exit 4" '[ "$RC" -eq 4 ]'
check "  failed: no answer.md / no DONE / state failed" '[ ! -e "$OUT/answer.md" ] && [ ! -e "$OUT/DONE" ] && [ "$(state_of "$OUT")" = failed ]'

new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_TASK_EXIT=3 "$OUT"
check "non-zero exit with valid-looking JSON → exit 4" '[ "$RC" -eq 4 ] && [ ! -e "$OUT/answer.md" ]'

new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_STATUS=1 "$OUT"
check "status 1 with exit 0 → exit 5" '[ "$RC" -eq 5 ] && [ ! -e "$OUT/answer.md" ]'

new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_STATUS='"completed"' "$OUT"
check "status \"completed\" (string) → exit 5" '[ "$RC" -eq 5 ] && [ ! -e "$OUT/answer.md" ]'

new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_TASK_STDOUT='Codex finished. {not json' "$OUT"
check "invalid JSON → exit 5" '[ "$RC" -eq 5 ] && [ ! -e "$OUT/answer.md" ]'

new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_RAW_OUTPUT=$'  \n\t ' "$OUT"
check "exit 0 + whitespace-only rawOutput → exit 5" '[ "$RC" -eq 5 ] && [ ! -e "$OUT/answer.md" ] && [ ! -e "$OUT/answer.md.tmp" ]'

new_out
run CODEX_COMPANION_PATH="$MOCK" MOCK_TOUCHED='["src/a.ts"]' "$OUT"
check "touchedFiles not empty → exit 5" '[ "$RC" -eq 5 ] && [ ! -e "$OUT/answer.md" ] && [ ! -e "$OUT/meta.json" ]'

echo "== success output =="
new_out; LOG="$TEST_DIR/args-success.log"
RAW=$'# Answer\n\nline with trailing spaces   \n'
run CODEX_COMPANION_PATH="$MOCK" MOCK_ARGS_LOG="$LOG" MOCK_RAW_OUTPUT="$RAW" \
  MOCK_THREAD_ID="01a0a631-95b1-7f20-b684-8f1b05b64fa3" "$OUT"
check "success → exit 0" '[ "$RC" -eq 0 ]'
check "answer.md == rawOutput (byte-exact)" '[ "$(cat "$OUT/answer.md"; printf x)" = "${RAW}x" ]'
check "meta.json has raw threadId, status 0, empty touchedFiles, duration" \
  'node -e "const m=JSON.parse(require(\"fs\").readFileSync(process.argv[1],\"utf8\")); process.exit(m.threadId===\"01a0a631-95b1-7f20-b684-8f1b05b64fa3\" && m.status===0 && Array.isArray(m.touchedFiles) && m.touchedFiles.length===0 && typeof m.duration_sec===\"number\" ? 0 : 1)" "$OUT/meta.json"'
check "DONE exists and state succeeded" '[ -f "$OUT/DONE" ] && [ "$(state_of "$OUT")" = succeeded ]'
check "no leftover .tmp files" '! ls "$OUT"/*.tmp >/dev/null 2>&1'
check "status.json records pid and prompt sha256" \
  'node -e "const s=JSON.parse(require(\"fs\").readFileSync(process.argv[1],\"utf8\")); process.exit(Number.isInteger(s.pid) && /^[0-9a-f]{64}$/.test(s.prompt_sha256) ? 0 : 1)" "$OUT/status.json"'

TASK_LINE="$(grep '"task"' "$LOG")"
check "task is always --fresh" 'echo "$TASK_LINE" | grep -q "\"--fresh\""'
check "task never gets --write / --resume-last / --resume / --background" \
  '! echo "$TASK_LINE" | grep -qE "\"--(write|resume-last|resume|background)\""'
check "task gets --json" 'echo "$TASK_LINE" | grep -q "\"--json\""'
check "--cwd passes the target repo to task and setup" \
  '[ "$(grep -c "\"--cwd\",\"$TARGET\"" "$LOG")" -eq 2 ]'
check "--prompt-file passed as absolute path" 'echo "$TASK_LINE" | grep -q "\"--prompt-file\",\"$PROMPT\""'
check "no --model / --effort when not specified" '! echo "$TASK_LINE" | grep -qE "\"--(model|effort)\""'

new_out; LOG="$TEST_DIR/args-model.log"
run CODEX_COMPANION_PATH="$MOCK" MOCK_ARGS_LOG="$LOG" "$OUT" --model gpt-test-mini --effort low
TASK_LINE="$(grep '"task"' "$LOG")"
check "--model / --effort passed through" \
  '[ "$RC" -eq 0 ] && echo "$TASK_LINE" | grep -q "\"--model\",\"gpt-test-mini\"" && echo "$TASK_LINE" | grep -q "\"--effort\",\"low\""'
check "meta.json records model / effort" 'grep -q "gpt-test-mini" "$OUT/meta.json" && grep -q "\"low\"" "$OUT/meta.json"'

echo "== stale shared broker =="
# A stale broker record in the normal plugin data dir must not make setup report "not logged in".
STALE_DATA="$TEST_DIR/plugin-data"
mkdir -p "$STALE_DATA"
: > "$STALE_DATA/stale-broker"
new_out; LOG="$TEST_DIR/args-stale.log"
run CODEX_COMPANION_PATH="$MOCK" CLAUDE_PLUGIN_DATA="$STALE_DATA" MOCK_ARGS_LOG="$LOG" "$OUT"
check "stale broker record → setup runs isolated → exit 0" '[ "$RC" -eq 0 ]'
check "  setup got a throwaway CLAUDE_PLUGIN_DATA, task kept the caller's" \
  'node -e "
    const lines = require(\"fs\").readFileSync(process.argv[1], \"utf8\").trim().split(\"\\n\").map(JSON.parse);
    const setup = lines.find((l) => l.argv[0] === \"setup\"), task = lines.find((l) => l.argv[0] === \"task\");
    process.exit(setup.pluginData && setup.pluginData !== process.argv[2] && task.pluginData === process.argv[2] ? 0 : 1);
  " "$LOG" "$STALE_DATA"'
check "  throwaway setup data dir is removed" \
  '[ ! -e "$(node -e "console.log(JSON.parse(require(\"fs\").readFileSync(process.argv[1],\"utf8\").split(\"\\n\")[0]).pluginData)" "$LOG")" ]'

echo "== argument validation =="
for bad in "--write" "--resume-last" "--resume" "--background"; do
  new_out; LOG="$TEST_DIR/args-bad-$N.log"
  run CODEX_COMPANION_PATH="$MOCK" MOCK_ARGS_LOG="$LOG" "$OUT" "$bad"
  check "$bad rejected (exit 1, companion not invoked)" '[ "$RC" -eq 1 ] && [ ! -e "$LOG" ]'
done

new_out; LOG="$TEST_DIR/args-effort.log"
run CODEX_COMPANION_PATH="$MOCK" MOCK_ARGS_LOG="$LOG" "$OUT" --effort extreme
check "invalid --effort rejected (exit 1, companion not invoked)" '[ "$RC" -eq 1 ] && [ ! -e "$LOG" ]'

RC=0
new_out
HOME="$FAKE_HOME" CODEX_COMPANION_PATH="$MOCK" "$RUNNER" --prompt-file prompt.md --cwd "$TARGET" --out-dir "$OUT" >/dev/null 2>&1 || RC=$?
check "relative --prompt-file rejected" '[ "$RC" -eq 1 ]'

new_out
run CODEX_COMPANION_PATH="$MOCK" "$OUT"
FIRST_RC="$RC"
run CODEX_COMPANION_PATH="$MOCK" "$OUT"
check "reusing an attempt directory is refused (no duplicate submission)" '[ "$FIRST_RC" -eq 0 ] && [ "$RC" -eq 1 ] && [ -f "$OUT/answer.md" ]'

new_out
CLAIM_PIDS=()
for _ in 1 2 3 4; do
  HOME="$FAKE_HOME" CODEX_COMPANION_PATH="$MOCK" MOCK_DELAY_SEC=1 \
    "$RUNNER" --prompt-file "$PROMPT" --cwd "$TARGET" --out-dir "$OUT" >/dev/null 2>&1 &
  CLAIM_PIDS+=("$!")
done
CLAIM_OK=0; CLAIM_REFUSED=0
for p in "${CLAIM_PIDS[@]}"; do
  prc=0; wait "$p" || prc=$?
  if [ "$prc" -eq 0 ]; then CLAIM_OK=$((CLAIM_OK + 1)); elif [ "$prc" -eq 1 ]; then CLAIM_REFUSED=$((CLAIM_REFUSED + 1)); fi
done
check "concurrent runs on one attempt dir: exactly one runs, the rest exit 1" '[ "$CLAIM_OK" -eq 1 ] && [ "$CLAIM_REFUSED" -eq 3 ]'

echo "== running state =="
new_out
HOME="$FAKE_HOME" CODEX_COMPANION_PATH="$MOCK" MOCK_DELAY_SEC=2 \
  "$RUNNER" --prompt-file "$PROMPT" --cwd "$TARGET" --out-dir "$OUT" >/dev/null 2>&1 &
BG_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$OUT/status.json" ] && break
  sleep 0.2
done
check "while running: state running, pid alive, no DONE/answer.md" \
  '[ "$(state_of "$OUT")" = running ] && kill -0 "$(node -e "console.log(JSON.parse(require(\"fs\").readFileSync(process.argv[1],\"utf8\")).pid)" "$OUT/status.json")" && [ ! -e "$OUT/DONE" ] && [ ! -e "$OUT/answer.md" ]'
wait "$BG_PID"
check "after completion: DONE and succeeded" '[ -f "$OUT/DONE" ] && [ "$(state_of "$OUT")" = succeeded ]'

echo ""
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
