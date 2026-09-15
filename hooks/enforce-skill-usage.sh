#!/usr/bin/env bash
# enforce-skill-usage.sh - PreToolUse command hook for codex-collab
#
# Enforces that codex-collab operations use skills instead of direct Bash.
# Type: command (works in both foreground and background agents)
#
# Protocol (Claude Code hook):
#   Input:  JSON via stdin with .tool_input.command
#   Output: exit 0 = allow, exit 2 = block (stderr shown to user)

# Require jq for JSON parsing; fail open if unavailable
command -v jq &>/dev/null || exit 0

# Read and extract command from tool input
COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Skill context marker — soft guard opt-in, only honored at line start
echo "$COMMAND" | grep -qE '^[[:space:]]*export[[:space:]]+CODEX_SKILL_CONTEXT=1' && exit 0

# Soft guard: only side-effect helpers (external execution / review / session-state writes).
# The load_* helpers are included because they migrate legacy state files in place.
# Pure transforms (codex_strip_ansi, codex_extract_thread_id etc.) and speculative
# sourcing/variable patterns are intentionally NOT guarded — see docs/bash-usage.md "Sunset criteria".
# Names are listed explicitly: \b does not match run_exec -> run_exec_session.
PATTERN='(^|[;&|]|\$\(|`)[[:space:]]*codex_(run_exec|run_exec_session|run_review|save_session_state|save_thread|save_thread_session|load_session_state|load_session_thread|load_thread|load_thread_sandbox)\b'

if echo "$COMMAND" | grep -qE "$PATTERN"; then
  cat >&2 << 'MSG'
This command calls a codex-collab side-effect helper directly
(codex_run_exec / codex_run_exec_session / codex_run_review /
 codex_save_session_state / codex_save_thread / codex_save_thread_session /
 codex_load_session_state / codex_load_session_thread / codex_load_thread / codex_load_thread_sandbox).

This is a soft guard against accidental direct use of internal APIs,
not a security boundary. Preferred entry points:
- /codex-collab [task] - Start collaboration
- /strong-inference [problem] - Investigate problems
- /devils-advocate [proposal] - Stress-test designs

If you are doing this intentionally, start the line with:
  export CODEX_SKILL_CONTEXT=1; <your command>

See docs/bash-usage.md for details.
MSG
  exit 2
fi

exit 0
