#!/usr/bin/env bash
# run-codex-role.sh — run one Codex role (always a fresh thread, read-only) through
# the official codex-plugin-cc companion and write a validated answer.
#
# Usage:
#   run-codex-role.sh --prompt-file <abs> --cwd <target repo> --out-dir <abs>
#                     [--model <model>] [--effort <none|minimal|low|medium|high|xhigh>]
#
# Output contract (out-dir is one role-attempt directory and is used only once):
#   .claimed/     created atomically (mkdir) before anything else; a second run on the same dir exits 1
#   status.json   written at start: {state: running, pid, started_at, prompt_sha256}
#                 updated at end:   state succeeded | failed (+ exit_code, finished_at)
#   answer.md     companion rawOutput (only on success; written via .tmp + mv)
#   meta.json     {threadId, status, touchedFiles, duration_sec, model, effort} (only on success)
#   DONE          created after answer.md and meta.json are in place (only on success)
#   error.log     reason for failure (only on failure)
#   companion-stdout.json / companion-stderr.log   raw companion output (debugging)
#
# Exit codes:
#   0 success
#   1 usage error (bad arguments, out-dir already used)
#   2 Codex unavailable (companion not installed, node missing, Codex CLI missing / not logged in)
#   4 execution failed (companion exited non-zero: turn failure, usage limit, crash)
#   5 invalid result (bad JSON, status != 0, empty rawOutput, touchedFiles not empty)
#
# Environment overrides (tests / failure injection; never touch global settings):
#   CODEX_COMPANION_PATH                path to codex-companion.mjs (skips discovery)
#   INSTALLED_PLUGINS_JSON              default ~/.claude/plugins/installed_plugins.json
#   CODEX_COMPANION_NO_CACHE_FALLBACK=1 disable the plugin cache semver fallback
#
# There is intentionally no --write and no --resume/--resume-last: every call is --fresh.

set -euo pipefail

PROMPT_FILE=""
TARGET_CWD=""
OUT_DIR=""
MODEL=""
EFFORT=""

usage_error() {
  echo "run-codex-role.sh: $1" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file) [ $# -ge 2 ] || usage_error "$1 requires a value"; PROMPT_FILE="$2"; shift 2 ;;
    --cwd)         [ $# -ge 2 ] || usage_error "$1 requires a value"; TARGET_CWD="$2"; shift 2 ;;
    --out-dir)     [ $# -ge 2 ] || usage_error "$1 requires a value"; OUT_DIR="$2"; shift 2 ;;
    --model)       [ $# -ge 2 ] || usage_error "$1 requires a value"; MODEL="$2"; shift 2 ;;
    --effort)      [ $# -ge 2 ] || usage_error "$1 requires a value"; EFFORT="$2"; shift 2 ;;
    --write|--resume|--resume-last|--background)
      usage_error "$1 is not supported (roles are always --fresh and read-only)"
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

[ -n "$PROMPT_FILE" ] || usage_error "--prompt-file is required"
[ -n "$TARGET_CWD" ] || usage_error "--cwd is required"
[ -n "$OUT_DIR" ] || usage_error "--out-dir is required"
case "$PROMPT_FILE" in /*) ;; *) usage_error "--prompt-file must be an absolute path" ;; esac
case "$OUT_DIR" in /*) ;; *) usage_error "--out-dir must be an absolute path" ;; esac
[ -f "$PROMPT_FILE" ] || usage_error "prompt file not found: $PROMPT_FILE"
[ -d "$TARGET_CWD" ] || usage_error "--cwd is not a directory: $TARGET_CWD"
if [ -n "$MODEL" ]; then
  case "$MODEL" in -*|*[[:space:]]*) usage_error "invalid --model: $MODEL" ;; esac
fi
if [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    none|minimal|low|medium|high|xhigh) ;;
    *) usage_error "invalid --effort: $EFFORT (none|minimal|low|medium|high|xhigh)" ;;
  esac
fi

mkdir -p "$OUT_DIR"
# Catches a directory that carries results from elsewhere (a seeded fixture, a copied
# attempt) — such a directory has no .claimed marker, so the claim below would let it run.
if [ -e "$OUT_DIR/status.json" ] || [ -e "$OUT_DIR/DONE" ]; then
  usage_error "out-dir already used (status.json or DONE exists): $OUT_DIR — use a new attempt directory"
fi
# Atomic claim: mkdir fails if another process already claimed this attempt directory.
# The marker is kept so the directory can never be reused.
if ! mkdir "$OUT_DIR/.claimed" 2>/dev/null; then
  usage_error "out-dir already claimed by another run: $OUT_DIR — use a new attempt directory"
fi

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

STARTED_AT="$(now_iso)"
START_EPOCH="$(date +%s)"
PROMPT_SHA="$(sha256_of "$PROMPT_FILE")"

# status.json is plain ASCII (pid, timestamps, hex digest), so printf is safe here.
write_status() {
  local state="$1" exit_code="${2:-}"
  local extra=""
  if [ -n "$exit_code" ]; then
    extra=", \"exit_code\": $exit_code, \"finished_at\": \"$(now_iso)\""
  fi
  printf '{"state": "%s", "pid": %s, "started_at": "%s", "prompt_sha256": "%s"%s}\n' \
    "$state" "$$" "$STARTED_AT" "$PROMPT_SHA" "$extra" > "$OUT_DIR/status.json.tmp"
  mv "$OUT_DIR/status.json.tmp" "$OUT_DIR/status.json"
}

fail() {
  local code="$1" msg="$2"
  printf '%s exit=%s %s\n' "$(now_iso)" "$code" "$msg" >> "$OUT_DIR/error.log"
  write_status failed "$code"
  echo "run-codex-role.sh: $msg" >&2
  exit "$code"
}

write_status running

# ── Resolve companion ────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || fail 2 "node not found (codex-plugin-cc companion requires node)"

COMPANION=""
if [ -n "${CODEX_COMPANION_PATH:-}" ]; then
  [ -f "$CODEX_COMPANION_PATH" ] || fail 2 "CODEX_COMPANION_PATH not found: $CODEX_COMPANION_PATH"
  COMPANION="$CODEX_COMPANION_PATH"
else
  PLUGINS_JSON="${INSTALLED_PLUGINS_JSON:-$HOME/.claude/plugins/installed_plugins.json}"
  if [ -f "$PLUGINS_JSON" ]; then
    INSTALL_PATH="$(node -e '
      const fs = require("fs");
      try {
        const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const entries = data && data.plugins && data.plugins["codex@openai-codex"];
        if (Array.isArray(entries) && entries.length > 0) {
          const pick = entries.find((e) => e && e.scope === "user") || entries[0];
          if (pick && typeof pick.installPath === "string") process.stdout.write(pick.installPath);
        }
      } catch (_) { /* unreadable -> fall through to cache */ }
    ' "$PLUGINS_JSON" 2>/dev/null || true)"
    if [ -n "$INSTALL_PATH" ] && [ -f "$INSTALL_PATH/scripts/codex-companion.mjs" ]; then
      COMPANION="$INSTALL_PATH/scripts/codex-companion.mjs"
    fi
  fi
  if [ -z "$COMPANION" ] && [ "${CODEX_COMPANION_NO_CACHE_FALLBACK:-}" != "1" ]; then
    CACHE_DIR="$HOME/.claude/plugins/cache/openai-codex/codex"
    if [ -d "$CACHE_DIR" ]; then
      # semver sort in node (portable; GNU find -printf / sort -V are not available everywhere)
      LATEST="$(node -e '
        const fs = require("fs");
        const vers = fs.readdirSync(process.argv[1]).filter((v) => /^\d+\.\d+\.\d+$/.test(v));
        vers.sort((a, b) => {
          const pa = a.split(".").map(Number), pb = b.split(".").map(Number);
          for (let i = 0; i < 3; i++) if (pa[i] !== pb[i]) return pa[i] - pb[i];
          return 0;
        });
        if (vers.length) process.stdout.write(vers[vers.length - 1]);
      ' "$CACHE_DIR" 2>/dev/null || true)"
      if [ -n "$LATEST" ] && [ -f "$CACHE_DIR/$LATEST/scripts/codex-companion.mjs" ]; then
        COMPANION="$CACHE_DIR/$LATEST/scripts/codex-companion.mjs"
      fi
    fi
  fi
  [ -n "$COMPANION" ] || fail 2 "codex-plugin-cc companion not found (install codex@openai-codex)"
fi

# ── Preflight: companion setup must report Codex ready ───────────────
SETUP_JSON="$OUT_DIR/companion-setup.json"
# setup's auth check reuses the workspace's recorded shared broker (broker.json) without
# checking it is alive. After a reboot that record points at a deleted /tmp socket and
# setup reports loggedIn:false even though Codex works (task itself replaces a stale broker).
# Run setup against an empty, throwaway plugin data dir so it checks auth directly.
SETUP_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/run-codex-role-setup.XXXXXX")"
SETUP_RC=0
CLAUDE_PLUGIN_DATA="$SETUP_DATA_DIR" node "$COMPANION" setup --json --cwd "$TARGET_CWD" \
  > "$SETUP_JSON" 2>> "$OUT_DIR/companion-stderr.log" || SETUP_RC=$?
rm -rf "$SETUP_DATA_DIR"
if [ "$SETUP_RC" -ne 0 ]; then
  fail 2 "companion setup failed (see companion-stderr.log)"
fi
if ! node -e '
  const fs = require("fs");
  const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const ok = r && r.ready === true && r.codex && r.codex.available === true && r.auth && r.auth.loggedIn === true;
  process.exit(ok ? 0 : 1);
' "$SETUP_JSON" 2>/dev/null; then
  fail 2 "Codex not ready (setup: ready / codex.available / auth.loggedIn must all be true)"
fi

# ── Run the role ─────────────────────────────────────────────────────
TASK_ARGS=(task --fresh --json --prompt-file "$PROMPT_FILE" --cwd "$TARGET_CWD")
[ -z "$MODEL" ] || TASK_ARGS+=(--model "$MODEL")
[ -z "$EFFORT" ] || TASK_ARGS+=(--effort "$EFFORT")

STDOUT_FILE="$OUT_DIR/companion-stdout.json"
TASK_RC=0
node "$COMPANION" "${TASK_ARGS[@]}" > "$STDOUT_FILE" 2>> "$OUT_DIR/companion-stderr.log" || TASK_RC=$?
if [ "$TASK_RC" -ne 0 ]; then
  fail 4 "companion task exited $TASK_RC (see companion-stderr.log / companion-stdout.json)"
fi

DURATION=$(( $(date +%s) - START_EPOCH ))

# Validate and write answer.md.tmp / meta.json.tmp in one pass.
VALIDATION_RC=0
VALIDATION_MSG="$(node -e '
  const fs = require("fs");
  const [stdoutFile, outDir, duration, model, effort] = process.argv.slice(1);
  let r;
  try { r = JSON.parse(fs.readFileSync(stdoutFile, "utf8")); }
  catch (e) { console.log("invalid JSON from companion task"); process.exit(5); }
  if (!r || typeof r !== "object") { console.log("companion JSON is not an object"); process.exit(5); }
  if (r.status !== 0) { console.log("status is not numeric 0: " + JSON.stringify(r.status)); process.exit(5); }
  if (typeof r.rawOutput !== "string" || r.rawOutput.trim() === "") { console.log("empty rawOutput"); process.exit(5); }
  if (!Array.isArray(r.touchedFiles)) { console.log("touchedFiles missing"); process.exit(5); }
  if (r.touchedFiles.length > 0) { console.log("touchedFiles not empty: " + JSON.stringify(r.touchedFiles)); process.exit(5); }
  if (typeof r.threadId !== "string" || r.threadId === "") { console.log("threadId missing"); process.exit(5); }
  fs.writeFileSync(outDir + "/answer.md.tmp", r.rawOutput);
  const meta = {
    threadId: r.threadId,
    status: r.status,
    touchedFiles: r.touchedFiles,
    duration_sec: Number(duration),
    model: model || null,
    effort: effort || null
  };
  fs.writeFileSync(outDir + "/meta.json.tmp", JSON.stringify(meta, null, 2) + "\n");
' "$STDOUT_FILE" "$OUT_DIR" "$DURATION" "$MODEL" "$EFFORT" 2>&1)" || VALIDATION_RC=$?

if [ "$VALIDATION_RC" -ne 0 ]; then
  rm -f "$OUT_DIR/answer.md.tmp" "$OUT_DIR/meta.json.tmp"
  fail 5 "invalid result: ${VALIDATION_MSG:-validation failed}"
fi

mv "$OUT_DIR/answer.md.tmp" "$OUT_DIR/answer.md"
mv "$OUT_DIR/meta.json.tmp" "$OUT_DIR/meta.json"
: > "$OUT_DIR/DONE"
write_status succeeded 0
exit 0
