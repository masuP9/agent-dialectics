#!/usr/bin/env bash
# codex-helpers.sh - Shared helper functions for codex-collab commands
#
# Usage:
#   # Source this file at the beginning of bash blocks in commands
#   HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
#   if [ -f "$HELPERS" ]; then
#     source "$HELPERS"
#   fi

# Guard against multiple sourcing
if [ -n "${_CODEX_HELPERS_LOADED:-}" ]; then
  # shellcheck disable=SC2317 # exit 0 is intentional fallback: return succeeds when sourced, exit 0 when executed directly
  return 0 2>/dev/null || exit 0
fi
_CODEX_HELPERS_LOADED=1

# ==============================================================================
# Configuration
# ==============================================================================

# Default values (can be overridden before sourcing)
: "${CODEX_WAIT_TIMEOUT:=180}"      # seconds (max 600 for Bash tool)

# Temporary directory for all working files
: "${CODEX_TMP_DIR:=./tmp}"

# ==============================================================================
# Language Directive
# ==============================================================================

# Get language directive prefix for Codex prompts
# Usage: directive=$(codex_get_language_directive "ja")
# Returns: Language instruction string (empty if lang is "en" or not set)
#
# When language is set to a non-English value (e.g., "ja"), this function
# returns a directive to be prepended to Codex prompts. The directive includes:
# - Main response language instruction
# - Thinking/reasoning process language instruction
#
# Examples:
#   "ja" -> "**jaで回答してください。途中の説明や思考プロセスも日本語で記述してください。**"
#   "zh" -> "**zhで回答してください。途中の説明や思考プロセスもzhで記述してください。**"
#   "en" -> (empty, no directive needed)
codex_get_language_directive() {
  local lang="${1:-en}"

  # No directive needed for English (default)
  if [ "$lang" = "en" ] || [ -z "$lang" ]; then
    return 0
  fi

  # Return language-specific directive with thinking process instruction
  # For Japanese, use natural phrasing
  if [ "$lang" = "ja" ]; then
    echo "**日本語で回答してください。途中の説明や思考プロセスも日本語で記述してください。**"
  else
    echo "**${lang}で回答してください。途中の説明や思考プロセスも${lang}で記述してください。**"
  fi
  echo ""
}

# ==============================================================================
# Debug Logging
# ==============================================================================

# Debug logging (enabled with CODEX_DEBUG=1)
# Usage: codex_debug "message"
codex_debug() {
  if [ "${CODEX_DEBUG:-}" = "1" ]; then
    echo "[codex-debug] $*" >&2
  fi
}

# ==============================================================================
# Directory Setup
# ==============================================================================

# Ensure tmp directory exists and return absolute path
# Usage: codex_ensure_tmp_dir
# Returns: Absolute path to tmp directory (e.g., /full/path/to/project/tmp)
codex_ensure_tmp_dir() {
  local rel_dir="${CODEX_TMP_DIR:-tmp}"
  # Remove leading ./ if present
  rel_dir="${rel_dir#./}"
  # Create absolute path
  local tmp_dir
  tmp_dir="$(pwd)/${rel_dir}"
  if [ ! -d "$tmp_dir" ]; then
    mkdir -p "$tmp_dir"
  fi
  echo "$tmp_dir"
}

# Get path in tmp directory
# Usage: path=$(codex_tmp_path "filename.txt")
codex_tmp_path() {
  local filename="$1"
  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  echo "${tmp_dir}/${filename}"
}

# ==============================================================================
# Hash Functions
# ==============================================================================

# Cross-platform hash function (md5sum on Linux, md5 on macOS)
# Usage: echo "content" | codex_hash_content
codex_hash_content() {
  if command -v md5sum &>/dev/null; then
    md5sum | awk '{print $1}'
  else
    md5
  fi
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Generate unique signal/marker ID
# Usage: SIGNAL=$(codex_generate_signal "prefix")
codex_generate_signal() {
  local prefix="${1:-codex}"
  echo "${prefix}-$$-$(date +%s)-$RANDOM"
}

# ==============================================================================
# ANSI Escape Code Removal
# ==============================================================================

# Strip ANSI escape codes from text
# Usage: clean=$(codex_strip_ansi "$text")
#        cat file | codex_strip_ansi
# shellcheck disable=SC2120 # function intentionally works both with arg and via pipe (no-arg stdin mode)
codex_strip_ansi() {
  if [ $# -gt 0 ]; then
    printf '%s' "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g; s/\033][^\007\033]*\007//g; s/\033][^\007\033]*\033\\\\//g'
  else
    sed $'s/\033\\[[0-9;]*[a-zA-Z]//g; s/\033][^\007\033]*\007//g; s/\033][^\007\033]*\033\\\\//g'
  fi
}

# ==============================================================================
# Prompt File Writing
# ==============================================================================

# Write prompt content to a temporary file
# Usage: prompt_file=$(codex_write_prompt "$content" "plan")
# Returns: Path to the created prompt file
codex_write_prompt() {
  local content="$1"
  local prefix="${2:-prompt}"
  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local prompt_file="${tmp_dir}/codex-${prefix}-$$.txt"
  printf '%s' "$content" > "$prompt_file"
  echo "$prompt_file"
}

# ==============================================================================
# Codex Exec Command Building
# ==============================================================================

# Build codex exec command string
# Usage: cmd=$(codex_build_exec_command "prompt_file" "read-only" "o4-mini")
# Arguments:
#   prompt_file - Path to prompt file (will be piped via stdin)
#   sandbox     - Sandbox mode: read-only | workspace-write | danger-full-access (default: read-only)
#   model       - Model name (optional, uses codex default if empty)
# Returns: Command string ready for eval
codex_build_exec_command() {
  local prompt_file="$1"
  local sandbox="${2:-read-only}"
  local model="${3:-}"

  local cmd="codex exec"

  # Add sandbox option
  cmd="${cmd} -s \"${sandbox}\""

  # Add model option if specified
  if [ -n "$model" ]; then
    cmd="${cmd} -m \"${model}\""
  fi

  # Read from stdin via redirect (more reliable than pipe)
  cmd="${cmd} - < \"${prompt_file}\""

  echo "$cmd"
}

# ==============================================================================
# Codex Exec Runner
# ==============================================================================

# Run codex exec with full I/O handling
# Usage: codex_run_exec "prompt_file" "output_file" "read-only" "o4-mini"
# Arguments:
#   prompt_file - Path to prompt file
#   output_file - Path to save output (optional, defaults to tmp/codex-output-$$.md)
#   sandbox     - Sandbox mode (default: read-only)
#   model       - Model name (optional)
# Returns: Exit code from codex exec
# Side effects: Writes output to output_file, strips ANSI codes
codex_run_exec() {
  local prompt_file="$1"
  local output_file="${2:-$(codex_tmp_path "codex-output-$$.md")}"
  local sandbox="${3:-read-only}"
  local model="${4:-}"

  if [ ! -f "$prompt_file" ]; then
    echo "Error: prompt file not found: $prompt_file" >&2
    return 1
  fi

  # Check if codex is available
  if ! command -v codex &>/dev/null; then
    echo "Error: codex command not found" >&2
    return 1
  fi

  codex_debug "run_exec: prompt=$prompt_file output=$output_file sandbox=$sandbox model=$model"

  # Build command arguments
  local -a codex_args=(exec -s "$sandbox")
  if [ -n "$model" ]; then
    codex_args+=(-m "$model")
  fi
  codex_args+=(-)

  # Execute codex with stdin redirect and capture output
  # Use tee to save to file while also showing stdout
  # Strip ANSI escape codes from output
  # pipefail ensures codex's exit code propagates through the pipe
  local exit_code=0
  # shellcheck disable=SC2119 # codex_strip_ansi is used in pipe (stdin) mode here, not with $1
  (set -o pipefail; codex "${codex_args[@]}" < "$prompt_file" 2>&1 | codex_strip_ansi | tee "$output_file") || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    codex_debug "run_exec: codex exited with code $exit_code"
    echo "Warning: codex exec exited with code $exit_code" >&2
  fi

  codex_debug "run_exec: output saved to $output_file ($(wc -l < "$output_file") lines)"
  return "$exit_code"
}

# ==============================================================================
# Stateful Execution (codex exec --json + codex exec resume)
# ==============================================================================
#
# JSONL checks rely on the event line shape observed on codex-cli 0.154.0:
#   {"type":"thread.started","thread_id":"<uuid>"}  {"type":"turn.completed",...}
# If the shape changes, classification degrades to rc 4/5 (never auto-retried).

# Positive signature of a resume rejected before any turn started (0.154.0).
# Also emitted for threads removed with `codex delete`. Archived threads use a
# different message and are therefore classified as rc 4.
_CODEX_RESUME_NOT_FOUND_MSG="no rollout found for thread id"

# Resolve a file path to "<physical directory>/<basename>" without requiring the file to exist
# Usage: canon=$(_codex_canonical_path "$path")
# Returns: 1 if the parent directory does not exist
_codex_canonical_path() {
  local target="$1"
  local dir base
  dir=$(dirname -- "$target")
  base=$(basename -- "$target")
  dir=$(CDPATH='' builtin cd -- "$dir" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "${dir%/}" "$base"
}

# Check that every non-empty JSONL line has the expected top-level event shape
# Usage: _codex_jsonl_well_formed "$jsonl_file"
# Returns: 0 if the file is non-empty and all lines match, 1 otherwise
_codex_jsonl_well_formed() {
  local jsonl_file="$1"
  [ -s "$jsonl_file" ] || return 1
  local bad
  bad=$(command grep -v '^[[:space:]]*$' "$jsonl_file" | command grep -cvE '^\{"type":"[a-z_.]+".*\}$' || true)
  [ "$bad" = "0" ]
}

# Extract the thread id from the thread.started event of a codex exec --json log
# Usage: thread_id=$(codex_extract_thread_id "$jsonl_file")
# Returns: 0 and prints the id if exactly one distinct valid UUID is found, 1 otherwise
codex_extract_thread_id() {
  local jsonl_file="$1"
  [ -f "$jsonl_file" ] || return 1

  local ids
  ids=$(command grep -oE '^\{"type":"thread\.started","thread_id":"[^"]*"' "$jsonl_file" \
    | sed -E 's/.*"thread_id":"([^"]*)"$/\1/' \
    | sort -u || true)

  [ -n "$ids" ] || return 1
  [ "$(printf '%s\n' "$ids" | wc -l | tr -d ' ')" = "1" ] || return 1
  codex_is_valid_uuid "$ids" || return 1
  echo "$ids"
}

# Run codex exec as a resumable session (new thread, or continue an existing one)
# Usage:
#   rc=0
#   THREAD_ID=$(codex_run_exec_session "$PROMPT" "$OUTPUT" "$SANDBOX" "$MODEL" "$PREV_THREAD_ID") || rc=$?
# Arguments:
#   prompt_file - Prompt read from stdin
#   output_file - Final agent message (`-o`); the only source of truth for the response body
#   sandbox     - read-only | workspace-write | danger-full-access (keep one sandbox per thread)
#   model       - Optional model
#   thread_id   - Optional: resume this thread (UUID) instead of starting a new one
# Side effects: Writes <output without .md>.jsonl (stdout events) and .stderr.log
# Returns (evaluated in this order):
#   2 - precondition / local I/O error, codex was NOT started
#   3 - resume rejected before any turn started (thread not found); safe to rebuild
#       history into a new session ONCE
#   4 - outcome unknown: codex failed, JSONL missing/malformed, or no turn.completed.
#       Never auto-retry (a workspace-write turn may already have changed files)
#   5 - completed but result invalid: empty output, missing/ambiguous thread id,
#       or resumed thread id mismatch. Never auto-retry
#   0 - success; prints the thread id to stdout
# Never uses --last (may pick another workflow's thread) or --ephemeral (not resumable).
codex_run_exec_session() {
  local prompt_file="$1"
  local output_file="$2"
  local sandbox="${3:-read-only}"
  local model="${4:-}"
  local thread_id="${5:-}"

  if [ ! -f "$prompt_file" ]; then
    echo "Error: prompt file not found: $prompt_file" >&2
    return 2
  fi
  if [ -z "$output_file" ]; then
    echo "Error: output file not specified" >&2
    return 2
  fi
  if ! command -v codex &>/dev/null; then
    echo "Error: codex command not found" >&2
    return 2
  fi
  if ! codex_is_valid_sandbox "$sandbox"; then
    echo "Error: invalid sandbox: $sandbox" >&2
    return 2
  fi
  if [ -n "$thread_id" ] && ! codex_is_valid_uuid "$thread_id"; then
    echo "Error: invalid thread id (UUID required): $thread_id" >&2
    return 2
  fi

  local base="${output_file%.md}"
  local jsonl_file="${base}.jsonl"
  local stderr_file="${base}.stderr.log"

  # Outputs are deleted below, so they must never resolve to the prompt file
  # (e.g. PROMPT=tmp/x.md vs OUTPUT=./tmp/x.md, or a symlink/hard link).
  local prompt_canon out_canon
  if ! prompt_canon=$(_codex_canonical_path "$prompt_file"); then
    echo "Error: cannot resolve prompt path: $prompt_file" >&2
    return 2
  fi
  # NOTE: do not name this variable `path` — in zsh it is tied to $PATH
  local out_path
  for out_path in "$output_file" "$jsonl_file" "$stderr_file"; do
    if ! out_canon=$(_codex_canonical_path "$out_path"); then
      echo "Error: output directory does not exist: $out_path" >&2
      return 2
    fi
    if [ "$out_canon" = "$prompt_canon" ] || { [ -e "$out_path" ] && [ "$out_path" -ef "$prompt_file" ]; }; then
      echo "Error: output path collides with prompt file: $out_path" >&2
      return 2
    fi
  done

  # Stale results must never be mistaken for this run's results.
  # `command` bypasses user aliases/functions (e.g. zsh `rm` aliased to a list) when sourced interactively.
  command rm -f -- "$output_file" "$jsonl_file" "$stderr_file" 2>/dev/null || true
  if [ -e "$output_file" ] || [ -e "$jsonl_file" ] || [ -e "$stderr_file" ]; then
    echo "Error: could not clear previous output files for $output_file" >&2
    return 2
  fi
  if ! : > "$jsonl_file" 2>/dev/null || ! : > "$stderr_file" 2>/dev/null; then
    echo "Error: could not create log files next to $output_file" >&2
    return 2
  fi

  local -a codex_args=(exec -s "$sandbox")
  if [ -n "$model" ]; then
    codex_args+=(-m "$model")
  fi
  if [ -n "$thread_id" ]; then
    codex_args+=(resume "$thread_id")
  fi
  codex_args+=(--json -o "$output_file" -)

  codex_debug "run_exec_session: sandbox=$sandbox model=$model thread=${thread_id:-<new>} output=$output_file"

  local codex_exit=0
  codex "${codex_args[@]}" < "$prompt_file" > "$jsonl_file" 2> "$stderr_file" || codex_exit=$?

  if [ -n "$thread_id" ] && [ "$codex_exit" -ne 0 ] && [ ! -s "$jsonl_file" ] \
    && command grep -qF "${_CODEX_RESUME_NOT_FOUND_MSG} ${thread_id}" "$stderr_file"; then
    echo "Warning: thread $thread_id not found; history must be rebuilt in a new session" >&2
    return 3
  fi

  if [ "$codex_exit" -ne 0 ]; then
    echo "Warning: codex exec exited with code $codex_exit (outcome unknown, see $stderr_file)" >&2
    return 4
  fi
  if ! _codex_jsonl_well_formed "$jsonl_file"; then
    echo "Warning: codex event log missing or malformed: $jsonl_file" >&2
    return 4
  fi
  if ! command grep -qE '^\{"type":"turn\.completed"' "$jsonl_file"; then
    echo "Warning: no turn.completed event in $jsonl_file (outcome unknown)" >&2
    return 4
  fi

  local new_thread_id
  if ! new_thread_id=$(codex_extract_thread_id "$jsonl_file"); then
    echo "Warning: missing or ambiguous thread id in $jsonl_file" >&2
    return 5
  fi
  if [ -n "$thread_id" ] && [ "$new_thread_id" != "$thread_id" ]; then
    echo "Warning: resumed thread id mismatch (expected $thread_id, got $new_thread_id)" >&2
    return 5
  fi
  if [ ! -s "$output_file" ]; then
    echo "Warning: codex produced no final message: $output_file" >&2
    return 5
  fi

  echo "$new_thread_id"
}

# ==============================================================================
# Lightweight Metadata Extraction
# ==============================================================================

# Extract the metadata block from a response
# Usage: metadata=$(codex_extract_metadata "$response")
# Returns: The YAML content between --- markers (without the markers)
codex_extract_metadata() {
  local response="$1"

  # Extract the last --- ... --- block
  # Use awk to find and print the last complete block
  echo "$response" | awk '
    /^---$/ {
      if (in_block) {
        # End of block - save it
        last_block = block
        in_block = 0
        block = ""
      } else {
        # Start of block
        in_block = 1
        block = ""
      }
      next
    }
    in_block {
      if (block != "") {
        block = block "\n" $0
      } else {
        block = $0
      }
    }
    END {
      if (last_block != "") {
        print last_block
      }
    }
  '
}

# Get a simple field value from metadata
# Usage: value=$(codex_get_field "$metadata" "status")
codex_get_field() {
  local metadata="$1"
  local field="$2"

  echo "$metadata" | grep "^${field}:" | sed "s/^${field}: *//" | head -1 || true
}

# Get the status field (continue/stop)
# Usage: result=$(codex_get_status "$metadata")
# Returns: "continue" or "stop" (default: "stop")
codex_get_status() {
  local metadata="$1"
  local status_val
  status_val=$(codex_get_field "$metadata" "status")

  case "$status_val" in
    continue|stop)
      echo "$status_val"
      ;;
    *)
      echo "stop"  # Default to stop if not specified
      ;;
  esac
}

# Get the verdict field (pass/conditional/fail)
# Usage: verdict=$(codex_get_verdict "$metadata")
# Returns: "pass", "conditional", "fail", or empty
codex_get_verdict() {
  local metadata="$1"
  local verdict
  verdict=$(codex_get_field "$metadata" "verdict")

  case "$verdict" in
    pass|conditional|fail)
      echo "$verdict"
      ;;
    *)
      echo ""  # No verdict
      ;;
  esac
}

# ==============================================================================
# Codex Review Runner
# ==============================================================================

# Run codex review --uncommitted with full I/O handling
# Usage: codex_run_review "output_file" "model" "sandbox"
# Arguments:
#   output_file - Path to save output (optional, defaults to tmp/codex-review-output-$$.md)
#   model       - Model name (optional)
#   sandbox     - Sandbox mode (optional, default: read-only)
# Returns: Exit code (0=success, non-zero=fallback needed)
# Side effects: Writes output to output_file, strips ANSI codes
#
# Note: codex review --uncommitted does not accept a custom prompt as a
# positional argument. Custom review instructions should be provided via
# the fallback codex exec path instead.
#
# Note: codex review has no -s/--sandbox flag, so the sandbox mode is passed
# via -c sandbox_mode=. Without it, review inherits sandbox_mode from
# ~/.codex/config.toml, which may allow writes during a read-only task.
codex_run_review() {
  local output_file="${1:-$(codex_tmp_path "codex-review-output-$$.md")}"
  local model="${2:-}"
  local sandbox="${3:-read-only}"

  # Check if codex command exists
  if ! command -v codex &>/dev/null; then
    codex_debug "run_review: codex command not found"
    return 127
  fi

  # Check if codex review subcommand is available
  if ! codex review --help &>/dev/null 2>&1; then
    codex_debug "run_review: codex review subcommand not available"
    return 127
  fi

  codex_debug "run_review: output=$output_file model=$model sandbox=$sandbox"

  local -a base_args=(review --uncommitted -c "sandbox_mode=\"${sandbox}\"")
  local -a review_args=("${base_args[@]}")

  # Try with model config if specified
  if [ -n "$model" ]; then
    review_args+=(-c "model=\"${model}\"")
  fi

  local exit_code=0
  # shellcheck disable=SC2119 # codex_strip_ansi is used in pipe (stdin) mode here, not with $1
  (set -o pipefail; codex "${review_args[@]}" 2>&1 | codex_strip_ansi | tee "$output_file") || exit_code=$?

  # If model config caused failure, retry without it
  if [ "$exit_code" -ne 0 ] && [ -n "$model" ]; then
    codex_debug "run_review: retrying without model config (exit_code=$exit_code)"
    review_args=("${base_args[@]}")
    exit_code=0
    # shellcheck disable=SC2119 # codex_strip_ansi is used in pipe (stdin) mode here, not with $1
    (set -o pipefail; codex "${review_args[@]}" 2>&1 | codex_strip_ansi | tee "$output_file") || exit_code=$?
  fi

  # Empty or very short output is also a failure
  if [ "$exit_code" -eq 0 ] && [ ! -s "$output_file" ]; then
    codex_debug "run_review: output file is empty"
    exit_code=1
  fi

  if [ "$exit_code" -ne 0 ]; then
    codex_debug "run_review: codex review exited with code $exit_code"
  else
    codex_debug "run_review: output saved to $output_file ($(wc -l < "$output_file") lines)"
  fi

  return "$exit_code"
}

# ==============================================================================
# Verdict Inference
# ==============================================================================

# Infer verdict from review response using multiple strategies
# Usage: verdict=$(codex_infer_verdict "$response")
# Returns: "pass", "conditional", "fail", or empty (unable to determine)
# Exit code: 0=verdict determined, 1=unable to determine
#
# Strategy order:
#   1. Metadata block (verdict: pass/conditional/fail)
#   2. [P1]-[P4] priority markers ([P1]/[P2] → fail, [P3]/[P4] → conditional)
#   3. Unable to determine → empty string, exit 1 (caller should retry/fallback)
#
# Note: We intentionally do NOT infer "pass" from the absence of markers.
# A response without markers may contain plain-text negative feedback that
# would be misclassified as pass. The caller should retry with a prompt
# requesting explicit verdict or treat as "conditional".
codex_infer_verdict() {
  local response="$1"

  # Strategy 1: metadata block
  local metadata verdict
  metadata=$(codex_extract_metadata "$response")
  if [ -n "$metadata" ]; then
    verdict=$(codex_get_verdict "$metadata")
    if [ -n "$verdict" ]; then
      echo "$verdict"
      return 0
    fi
  fi

  # Strategy 2: [P1]-[P4] priority markers
  local has_p1 has_p2 has_p3 has_p4
  has_p1=$(echo "$response" | grep -c '\[P1\]' || true)
  has_p2=$(echo "$response" | grep -c '\[P2\]' || true)
  has_p3=$(echo "$response" | grep -c '\[P3\]' || true)
  has_p4=$(echo "$response" | grep -c '\[P4\]' || true)

  if [ "$has_p1" -gt 0 ] || [ "$has_p2" -gt 0 ]; then
    echo "fail"
    return 0
  elif [ "$has_p3" -gt 0 ] || [ "$has_p4" -gt 0 ]; then
    echo "conditional"
    return 0
  fi

  # Unable to determine - caller should retry or treat as conditional
  echo ""
  return 1
}

# ==============================================================================
# Session State Management (codex exec thread ids for exec resume)
# ==============================================================================

# Validate a Codex thread id (UUID 8-4-4-4-12). Non-UUID values are rejected because
# `codex exec resume <name>` silently starts a NEW thread for unknown names (0.154.0).
# Usage: codex_is_valid_uuid "$id" && ...
codex_is_valid_uuid() {
  printf '%s' "$1" | command grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

# Validate a sandbox mode value accepted by `codex exec -s`
# Usage: codex_is_valid_sandbox "$sandbox" && ...
codex_is_valid_sandbox() {
  case "$1" in
    read-only|workspace-write|danger-full-access) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract one field of a stored named-thread value ("<uuid>|<sandbox>")
# Usage: _codex_parse_thread_value "$value" uuid|sandbox
# Returns: 0 and prints the field if the value is well-formed, 1 otherwise
#          (legacy raw ids, missing/extra separators, invalid uuid or sandbox)
_codex_parse_thread_value() {
  local value="$1"
  local field="$2"
  case "$value" in
    *"|"*"|"*) return 1 ;;
    *"|"*) ;;
    *) return 1 ;;
  esac
  local uuid="${value%%|*}"
  local sandbox="${value#*|}"
  codex_is_valid_uuid "$uuid" || return 1
  codex_is_valid_sandbox "$sandbox" || return 1
  if [ "$field" = "uuid" ]; then
    echo "$uuid"
  else
    echo "$sandbox"
  fi
}

# Migrate a legacy session state file in place (mode "mcp"/"bash" -> "exec").
# MCP thread ids cannot be resumed by `codex exec resume`, so threadId and threads
# are cleared. Writes via temp file + mv so a partial file is never exposed.
# Usage: _codex_migrate_session_state "$state_file"
# Returns: 0 if already current or migrated, 2 if the rewrite failed
_codex_migrate_session_state() {
  local state_file="$1"
  [ -f "$state_file" ] || return 0

  local mode
  mode=$(command grep '"mode"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  case "$mode" in
    mcp|bash) ;;
    *) return 0 ;;
  esac

  local sandbox workflow task_id updated_at
  sandbox=$(command grep '"sandbox"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  workflow=$(command grep '"workflow"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  task_id=$(command grep '"taskId"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  updated_at=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)

  local tmp_file="${state_file}.migrate.$$"
  if ! cat > "$tmp_file" 2>/dev/null << EOJSON
{
  "mode": "exec",
  "threadId": "",
  "threads": {},
  "sandbox": "${sandbox}",
  "workflow": "${workflow}",
  "taskId": "${task_id}",
  "updatedAt": "${updated_at}"
}
EOJSON
  then
    command rm -f "$tmp_file" 2>/dev/null || true
    codex_debug "migrate_session_state: failed to write $tmp_file"
    return 2
  fi
  if ! command mv -f "$tmp_file" "$state_file" 2>/dev/null; then
    command rm -f "$tmp_file" 2>/dev/null || true
    codex_debug "migrate_session_state: failed to replace $state_file"
    return 2
  fi
  codex_debug "migrate_session_state: migrated $state_file (mode=$mode -> exec)"
  return 0
}

# Sanitize task_id for safe use in filenames (allow only alphanumerics, hyphens, underscores)
# Usage: safe_id=$(codex_sanitize_task_id "$raw_id")
codex_sanitize_task_id() {
  printf '%s' "$1" | tr -cd 'a-zA-Z0-9_-' | head -c 128
}

# Escape a string for safe JSON embedding (handles quotes, backslashes, newlines)
# Usage: escaped=$(codex_json_escape "$value")
codex_json_escape() {
  printf '%s' "$1" \
    | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' \
    | tr '\n' ' ' \
    | tr -d '\000-\010\013-\037'
}

# Save session state to a JSON file (task_id-scoped for concurrent isolation)
# Usage: codex_save_session_state "task_id" "exec" "thread_id" "read-only" "codex-leads"
# Arguments:
#   task_id   - Unique task identifier for isolation (sanitized for filename safety)
#   mode      - Communication mode: "exec" (legacy "mcp"/"bash" files are migrated on load)
#   thread_id - codex exec thread id from `codex_run_exec_session` (empty before the
#               first call). For claude-leads, use codex_save_thread_session() to store
#               named threads (threadB, threadC) together with their sandbox.
#   sandbox   - Sandbox mode
#   workflow  - Workflow type
# Side effects: Writes to tmp/codex-session-{task_id}.json
# State writes for one task_id must be serialized by the orchestrator (no locking).
codex_save_session_state() {
  local task_id
  task_id=$(codex_sanitize_task_id "$1")
  local mode="$2"
  local thread_id="${3:-}"
  local sandbox="${4:-read-only}"
  local workflow="${5:-codex-leads}"

  if [ -z "$task_id" ]; then
    codex_debug "save_session_state: empty task_id after sanitization"
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  local updated_at
  updated_at=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)

  # Escape values for JSON safety
  local esc_thread_id esc_sandbox esc_workflow
  esc_thread_id=$(codex_json_escape "$thread_id")
  esc_sandbox=$(codex_json_escape "$sandbox")
  esc_workflow=$(codex_json_escape "$workflow")

  # Legacy threads must not be carried over into an exec-mode file
  _codex_migrate_session_state "$state_file" || return 2

  # Preserve existing threads block if state file already exists
  local existing_threads_block="{}"
  if [ -f "$state_file" ]; then
    local threads_content
    threads_content=$(sed -n '/"threads":/,/}/{ /"threads":/d; /}/d; p; }' "$state_file" | grep -v '^$' || true)
    if [ -n "$threads_content" ]; then
      existing_threads_block="{
${threads_content}
  }"
    fi
  fi

  cat > "$state_file" << EOJSON
{
  "mode": "${mode}",
  "threadId": "${esc_thread_id}",
  "threads": ${existing_threads_block},
  "sandbox": "${esc_sandbox}",
  "workflow": "${esc_workflow}",
  "taskId": "${task_id}",
  "updatedAt": "${updated_at}"
}
EOJSON

  codex_debug "save_session_state: saved to $state_file (mode=$mode, threadId=$thread_id)"
  echo "$state_file"
}

# Save a named thread to session state (for multi-thread topology, e.g., claude-leads Thread B/C)
# Usage: codex_save_thread "task_id" "threadB" "thread-id-value"
codex_save_thread() {
  local task_id
  task_id=$(codex_sanitize_task_id "$1")
  local thread_name="$2"
  local thread_value="$3"

  if [ -z "$task_id" ]; then
    codex_debug "save_thread: empty task_id after sanitization"
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  if [ ! -f "$state_file" ]; then
    codex_debug "save_thread: state file not found: $state_file"
    return 1
  fi

  _codex_migrate_session_state "$state_file" || return 2

  # Read current threads block, add/update the named thread
  local esc_value
  esc_value=$(codex_json_escape "$thread_value")
  local esc_name
  esc_name=$(codex_json_escape "$thread_name")

  # Simple approach: read file, replace threads block
  # Extract existing threads content (between "threads": { and })
  local existing_threads
  existing_threads=$(sed -n '/"threads":/,/}/{ /"threads":/d; /}/d; p; }' "$state_file" | grep -v '^$' || true)

  # Build new threads block
  local new_threads=""
  if [ -n "$existing_threads" ]; then
    # Remove existing entry for this thread name if present, and trailing comma
    local filtered
    filtered=$(echo "$existing_threads" | grep -vF "\"${esc_name}\":" || true)
    if [ -n "$filtered" ]; then
      # Ensure trailing comma on existing entries
      new_threads=$(echo "$filtered" | sed 's/[[:space:]]*$//' | sed '$ s/,*$/,/')
      new_threads="${new_threads}
    \"${esc_name}\": \"${esc_value}\""
    else
      new_threads="    \"${esc_name}\": \"${esc_value}\""
    fi
  else
    new_threads="    \"${esc_name}\": \"${esc_value}\""
  fi

  # Rebuild file with updated threads
  local updated_at
  updated_at=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)

  local mode sandbox workflow threadId
  mode=$(grep '"mode"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  threadId=$(grep '"threadId"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  sandbox=$(grep '"sandbox"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  workflow=$(grep '"workflow"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)

  cat > "$state_file" << EOJSON
{
  "mode": "${mode}",
  "threadId": "${threadId}",
  "threads": {
${new_threads}
  },
  "sandbox": "${sandbox}",
  "workflow": "${workflow}",
  "taskId": "${task_id}",
  "updatedAt": "${updated_at}"
}
EOJSON

  codex_debug "save_thread: saved ${thread_name}=${thread_value} to $state_file"
}

# Save a named exec thread together with its sandbox (1 thread = 1 sandbox)
# Usage: codex_save_thread_session "task_id" "threadC" "$uuid" "workspace-write"
# Returns: 0 on success, 1 on invalid uuid/sandbox or missing state file, 2 on I/O failure
codex_save_thread_session() {
  local task_id="$1"
  local thread_name="$2"
  local uuid="$3"
  local sandbox="$4"

  if ! codex_is_valid_uuid "$uuid" || ! codex_is_valid_sandbox "$sandbox"; then
    codex_debug "save_thread_session: invalid uuid='$uuid' or sandbox='$sandbox'"
    return 1
  fi
  codex_save_thread "$task_id" "$thread_name" "${uuid}|${sandbox}"
}

# Read the raw stored value of a named thread (no validation, no migration).
# Internal: callers should use codex_load_thread / codex_load_thread_sandbox.
# Usage: value=$(_codex_load_thread_raw "task_id" "threadB")
_codex_load_thread_raw() {
  local task_id
  task_id=$(codex_sanitize_task_id "$1")
  local thread_name="$2"

  if [ -z "$task_id" ]; then
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  if [ ! -f "$state_file" ]; then
    return 1
  fi

  local esc_name
  esc_name=$(codex_json_escape "$thread_name")

  # A missing entry prints nothing (rc 0); a read error must surface as rc 2
  local content
  content=$(command cat -- "$state_file" 2>/dev/null) || return 2
  printf '%s\n' "$content" | command grep -F "\"${esc_name}\":" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true
}

# Shared implementation of codex_load_thread / codex_load_thread_sandbox
_codex_load_thread_field() {
  local task_id="$1"
  local thread_name="$2"
  local field="$3"

  local safe_id
  safe_id=$(codex_sanitize_task_id "$task_id")
  [ -n "$safe_id" ] || return 1

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${safe_id}.json"
  [ -f "$state_file" ] || return 1

  _codex_migrate_session_state "$state_file" || return 2

  local raw raw_rc=0
  raw=$(_codex_load_thread_raw "$task_id" "$thread_name") || raw_rc=$?
  [ "$raw_rc" -eq 2 ] && return 2
  [ "$raw_rc" -eq 0 ] || return 1
  [ -n "$raw" ] || return 1
  _codex_parse_thread_value "$raw" "$field"
}

# Load the thread id (UUID only) of a named thread
# Usage: rc=0; thread_id=$(codex_load_thread "task_id" "threadB") || rc=$?
# Returns: 0 = resumable thread id printed
#          1 = no thread saved, or legacy/malformed value (start a new session instead)
#          2 = state migration / I/O failure (stop; never fall back to a new session)
codex_load_thread() {
  _codex_load_thread_field "$1" "$2" uuid
}

# Load the sandbox a named thread was created with
# Usage: rc=0; sandbox=$(codex_load_thread_sandbox "task_id" "threadC") || rc=$?
# Returns: same codes as codex_load_thread
codex_load_thread_sandbox() {
  _codex_load_thread_field "$1" "$2" sandbox
}

# Load session state from a JSON file
# Usage: rc=0; codex_load_session_state "task_id" > /dev/null || rc=$?
# Returns: Prints JSON content to stdout
#          0 = loaded, 1 = not found / missing mode, 2 = legacy migration or read failure
# Side effects: Migrates legacy mode "mcp"/"bash" files to "exec" (threadId/threads cleared);
#   resets and then sets SESSION_MODE, SESSION_THREAD_ID, SESSION_SANDBOX, SESSION_WORKFLOW.
#   SESSION_THREAD_ID / SESSION_SANDBOX are emptied when not a valid UUID / sandbox.
#   To decide whether to resume, use codex_load_session_thread.
codex_load_session_state() {
  # Never leave values from a previous call behind
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""

  local task_id
  task_id=$(codex_sanitize_task_id "$1")

  if [ -z "$task_id" ]; then
    codex_debug "load_session_state: empty task_id after sanitization"
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  if [ ! -f "$state_file" ]; then
    codex_debug "load_session_state: file not found: $state_file"
    return 1
  fi

  _codex_migrate_session_state "$state_file" || return 2

  local content
  if ! content=$(command cat -- "$state_file" 2>/dev/null); then
    codex_debug "load_session_state: cannot read $state_file"
    return 2
  fi

  # Parse JSON fields using grep/sed (no jq dependency)
  # Guards with || true to prevent set -e failures on malformed files
  SESSION_MODE=$(printf '%s\n' "$content" | command grep '"mode"' | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  SESSION_THREAD_ID=$(printf '%s\n' "$content" | command grep '"threadId"' | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  # shellcheck disable=SC2034 # SESSION_SANDBOX is exported for use by callers that source this file
  SESSION_SANDBOX=$(printf '%s\n' "$content" | command grep '"sandbox"' | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  # shellcheck disable=SC2034 # SESSION_WORKFLOW is exported for use by callers that source this file
  SESSION_WORKFLOW=$(printf '%s\n' "$content" | command grep '"workflow"' | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)

  # Validate minimum required fields
  if [ -z "$SESSION_MODE" ]; then
    codex_debug "load_session_state: missing 'mode' field in $state_file"
    return 1
  fi

  # Never hand a non-resumable value to callers
  if [ -n "$SESSION_THREAD_ID" ] && ! codex_is_valid_uuid "$SESSION_THREAD_ID"; then
    codex_debug "load_session_state: ignoring invalid threadId '$SESSION_THREAD_ID'"
    SESSION_THREAD_ID=""
  fi
  if [ -n "$SESSION_SANDBOX" ] && ! codex_is_valid_sandbox "$SESSION_SANDBOX"; then
    codex_debug "load_session_state: ignoring invalid sandbox '$SESSION_SANDBOX'"
    # shellcheck disable=SC2034 # SESSION_SANDBOX is exported for use by callers that source this file
    SESSION_SANDBOX=""
  fi

  codex_debug "load_session_state: loaded from $state_file (mode=$SESSION_MODE, threadId=$SESSION_THREAD_ID)"
  printf '%s\n' "$content"
}

# Decide whether the main thread (Thread A etc.) can be resumed with a given sandbox
# Usage: rc=0; thread_id=$(codex_load_session_thread "task_id" "read-only") || rc=$?
# Returns: 0 = resumable UUID printed (saved thread exists and was created with this sandbox)
#          1 = no saved thread, legacy/invalid value, or sandbox mismatch
#              (start a new thread from the role's saved inputs — never resume)
#          2 = state migration / read failure (stop; never fall back to a new session)
codex_load_session_thread() {
  local task_id="$1"
  local sandbox="$2"

  local rc=0
  codex_load_session_state "$task_id" > /dev/null || rc=$?
  [ "$rc" -eq 2 ] && return 2
  [ "$rc" -eq 0 ] || return 1
  [ -n "$SESSION_THREAD_ID" ] || return 1
  if [ -n "$sandbox" ] && [ "$SESSION_SANDBOX" != "$sandbox" ]; then
    codex_debug "load_session_thread: sandbox mismatch (saved=$SESSION_SANDBOX requested=$sandbox)"
    return 1
  fi
  echo "$SESSION_THREAD_ID"
}

# ==============================================================================
# Diff Size Tiering
# ==============================================================================

# Determine diff tier based on line count
# Usage: tier=$(codex_diff_tier "$diff_content")
# Returns: "small" (<=500 lines), "medium" (501-2000), or "large" (>2000)
codex_diff_tier() {
  local diff_content="$1"

  local line_count
  if [ -z "$diff_content" ]; then
    line_count=0
  else
    line_count=$(printf '%s\n' "$diff_content" | wc -l)
  fi

  if [ "$line_count" -le 500 ]; then
    echo "small"
  elif [ "$line_count" -le 2000 ]; then
    echo "medium"
  else
    echo "large"
  fi
}

# ==============================================================================
# Review Findings Extraction
# ==============================================================================

# Extract review findings from response
# Usage: findings=$(codex_extract_review_findings "$response")
# Returns: Extracted findings text (from metadata findings: or [P1]-[P4] markers)
codex_extract_review_findings() {
  local response="$1"
  local findings=""

  # Strategy 1: metadata findings
  local metadata
  metadata=$(codex_extract_metadata "$response")
  if [ -n "$metadata" ]; then
    local meta_findings
    meta_findings=$(echo "$metadata" | awk '
      /^findings:/ { in_findings=1; next }
      in_findings && /^  - / { print substr($0, 5); next }
      in_findings && /^[^ ]/ { in_findings=0 }
    ')
    if [ -n "$meta_findings" ]; then
      findings="$meta_findings"
    fi
  fi

  # Strategy 2: [P1]-[P4] markers (append if metadata had no findings)
  if [ -z "$findings" ]; then
    local marker_findings
    marker_findings=$(echo "$response" | grep -E '\[P[1-4]\]' || true)
    if [ -n "$marker_findings" ]; then
      findings="$marker_findings"
    fi
  fi

  echo "$findings"
}
