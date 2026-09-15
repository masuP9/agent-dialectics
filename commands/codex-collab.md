---
name: codex-collab
description: Start a collaborative task with Codex (default: codex-leads workflow)
argument-hint: [task description]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# Codex Collaboration Workflow

Execute a collaborative workflow between Claude Code and Codex CLI.

**Workflow modes** (`workflow` setting):
- **codex-leads** (従来): Codex が計画・レビュー、Claude が実装
- **claude-leads** (新規): Claude が計画・レビュー、Codex が実装（workspace-write sandbox）
- **auto** (default): 常に codex-leads を選択（明示的に `claude-leads` を指定した場合のみ Claude 主導）

**Architecture**: Codex は `codex` CLI のみで操作する。新規ターンは `codex exec --json`、継続は `codex exec resume <thread_id>` でステートフルに会話し、thread id をセッション状態に保存する（codex-cli 0.154.0 以上）。

## Task

$ARGUMENTS

## Workflow Instructions

### Step 0: Load Helper Functions

Source shared helper functions at the beginning of any bash block. **Always set `CODEX_SKILL_CONTEXT=1`** to indicate skill context for the PreToolUse hook:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1

# Source helpers with robust fallback chain
# 1. Try CLAUDE_PLUGIN_ROOT if valid
# 2. Try Claude plugin cache (latest version)
# 3. Try current directory (for development)
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
else
  echo "Error: codex-helpers.sh not found" >&2
  echo "Tried: CLAUDE_PLUGIN_ROOT, ~/.claude/plugins/cache, $(pwd)" >&2
fi
```

> **Note:** Helper functions are required for this workflow. The loader tries multiple locations: `CLAUDE_PLUGIN_ROOT`, Claude plugin cache, and current directory.
> **Important:** The `CODEX_SKILL_CONTEXT=1` export is required for the PreToolUse hook to recognize this as skill context and allow Bash execution without blocking.

### Step 0a: Initialize Session

Codex is driven only through the `codex` CLI (`codex exec --json` / `codex exec resume` / `codex review`).

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

if ! command -v codex &>/dev/null; then
  echo "CODEX_NOT_AVAILABLE"
fi

TASK_ID="collab-$$-$(date +%s)"
# No thread yet: the first codex_run_exec_session call creates Thread A.
# Workflow/sandbox are updated after Step 1 loads settings.
codex_save_session_state "$TASK_ID" "exec" ""
echo "task_id: $TASK_ID"
```

- If `CODEX_NOT_AVAILABLE` is printed → see **Error Handling**.
- Shell variables do not survive between Bash tool calls. **Write the printed `task_id` literally** into later blocks (`TASK_ID="collab-..."`) and persist every thread id in session state immediately after it is obtained.

### Codex Call Protocol (used by every step that talks to Codex)

Every Codex turn goes through `codex_run_exec_session`:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-REPLACE"                 # value printed in Step 0a
PROMPT_FILE="$(pwd)/tmp/codex-plan-prompt.txt"
OUTPUT_FILE="$(pwd)/tmp/codex-plan-output.md"
SANDBOX="read-only"                       # must equal the sandbox the thread was created with
MODEL=""                                  # model setting, empty = Codex default

# Thread to continue: 0 = resumable (same sandbox), 1 = start a new thread, 2 = stop
load_rc=0
PREV_THREAD_ID=$(codex_load_session_thread "$TASK_ID" "$SANDBOX") || load_rc=$?
if [ "$load_rc" -eq 2 ]; then
  echo "STATE_IO_ERROR"
else
  if [ "$load_rc" -ne 0 ]; then
    PREV_THREAD_ID=""
    echo "NO_RESUMABLE_THREAD (the prompt must be self-contained / reconstructed)"
  fi
  rc=0
  NEW_THREAD_ID=$(codex_run_exec_session "$PROMPT_FILE" "$OUTPUT_FILE" "$SANDBOX" "$MODEL" "$PREV_THREAD_ID") || rc=$?
  echo "codex rc=$rc thread=$NEW_THREAD_ID"
  if [ "$rc" -eq 0 ]; then
    codex_save_session_state "$TASK_ID" "exec" "$NEW_THREAD_ID" "$SANDBOX" "codex-leads" > /dev/null
  fi
fi
```

Handle the result **by return code** (never by guessing from output text):

| rc | Meaning | Action |
|----|---------|--------|
| `0` | Turn completed | Read `OUTPUT_FILE` (the only source of the response body). Thread id is saved. |
| `2` | Precondition / local I/O error, Codex not started | Report and stop. |
| `3` | Resumed thread no longer exists (before any turn started) | **Only auto-recoverable case.** Rebuild context from this role's own inputs (see *History Reconstruction*), call once more with an **empty** thread id, save the new id. If that call fails too, report to the user. |
| `4` | Outcome unknown (Codex failed mid-turn, broken event log, no `turn.completed`) | **Do not retry automatically.** Show the tail of `${OUTPUT_FILE%.md}.stderr.log`. For workspace-write threads run `git status` / `git diff --stat` first. Ask the user (AskUserQuestion): retry / abandon / continue manually. |
| `5` | Turn completed but result invalid (empty output, thread id missing/mismatched) | Same as `4`. |

Additional rules:
- `STATE_IO_ERROR` (load rc=2) → stop; Codex is not called and no new session is created.
- `NO_RESUMABLE_THREAD` (load rc=1: no saved thread, legacy value, or a different sandbox) → the prompt must carry the role's full context (History Reconstruction) because a new thread is started; its id is saved on success.
- A turn's `OUTPUT_FILE` is deleted before the next call. Copy any response you may need for a later History Reconstruction (into `tmp/codex-history/$TASK_ID/`, and stop if the copy fails) before re-using the same output path.
- **One thread = one sandbox.** Never resume a thread with a different sandbox; use a separate named thread instead.
- Never use `codex exec resume --last` (it may pick another workflow's thread).
- State writes for one `TASK_ID` must happen sequentially (one Bash call at a time).
- Set the Bash tool `timeout` to `min(wait_timeout + 60, 600) * 1000` ms; use `run_in_background: true` for long turns.

#### History Reconstruction (rc=3 only)

Build a new prompt containing the role's inputs instead of the lost thread:
- **Direct recent rounds (last 2):** full text of the latest exchanges (from the output files)
- **Older rounds:** summarize key decisions, unresolved questions, constraints (`exchange.history_mode: summarize`)

```
## Conversation History (thread was lost; reconstructed)

### Previous Rounds Summary
[Key decisions, unresolved questions, constraints]

### Round {N-1}
Claude: [previous message]
Codex: [previous response]

## Continue Discussion
[Current message]
```

### Step 1: Load Settings

Check for project-specific settings:
- Read `.claude/codex-collab.local.md` if it exists
- Extract YAML frontmatter for: model, sandbox, codex, exchange, review, **workflow** settings
- Apply settings priority: command args > project settings > defaults

**Default settings:**
- **workflow**: auto (options: auto, codex-leads, claude-leads; auto は常に codex-leads を選択)
- model: (Codex default)
- sandbox: read-only (codex-leads) / workspace-write (claude-leads)
- language: en (Codex response language)
- **Timeout** (codex.*):
  - codex.wait_timeout: 180 (seconds, max 600)
- **Planning exchange** (exchange.*, codex-leads only):
  - exchange.enabled: true
  - exchange.max_iterations: 3
  - exchange.user_confirm: on_important
  - exchange.history_mode: summarize
- **Review iteration** (review.*, codex-leads only):
  - review.enabled: true
  - review.max_iterations: 5
  - review.max_verdict_retries: 3 (retries when verdict is missing/unclear)
  - review.user_confirm: never
- **Claude-leads specific** (claude_leads.*):
  - claude_leads.sandbox: workspace-write (Codex 実装用 sandbox)
  - claude_leads.consult_codex: true (壁打ちフェーズを有効化)
  - claude_leads.safety_checkpoint: stash (options: stash, wip-commit, none)
  - claude_leads.review.max_iterations: 3 (レビュー修正ループの上限)

**Language setting:**
When `language` is set to a non-English value (e.g., `ja`), all Codex prompts will be prefixed with a language directive:
```
**{language}で回答してください。**

[Original prompt content]
```

This ensures Codex responds in the specified language regardless of the prompt template language.

### Step 1a: Determine Workflow

After loading settings, determine which workflow to use:

**If `workflow` is explicitly set to `codex-leads` or `claude-leads`:**
- Use that workflow directly.

**If `workflow` is `auto` (default):**

Always select `codex-leads`.

> **Note:** `auto` は常に `codex-leads` を選択する。`claude-leads` はClaude側のコンテキスト/ターン消費が大きく、Codex実装待ちの間にタイムアウトする問題があるため、明示的に `workflow: claude-leads` を指定した場合のみ有効。

Report the selected workflow to the user:
```
Workflow: codex-leads (auto-selected, default)
```

**Update session state with resolved settings:**

After settings and workflow are determined, update the session state file (Step 0a saved only defaults):

```bash
export CODEX_SKILL_CONTEXT=1
# Re-save with resolved settings (TASK_ID from Step 0a; no thread yet)
codex_save_session_state "$TASK_ID" "exec" "" "${SANDBOX_SETTING:-read-only}" "${WORKFLOW:-codex-leads}"
```

**After workflow is determined:**
- If `codex-leads` → Continue to **Step 2** (existing workflow)
- If `claude-leads` → Jump to **Step 2c** (Claude-led workflow)

---

## Codex-Leads Workflow (従来のワークフロー)

> This is the default workflow where **Codex plans and reviews, Claude implements**.
> Active when `workflow` is `auto` (default) or explicitly set to `codex-leads`.

### Step 2: Analyze Task

**Before starting, create a task to track progress:**

Use TaskCreate:
- subject: "Analyze task and gather context"
- description: "Load settings, identify affected files, prepare context for Codex"
- activeForm: "Analyzing task"

Then use TaskUpdate to set status to `in_progress`.

**Perform analysis:**
1. Identify the core objective from the task description
2. List potentially affected files
3. Gather relevant context by reading key files
4. Prepare a summary for Codex

### Step 3: Request Plan from Codex

**Task transition:**
1. Mark "Analyze task and gather context" as `completed`
2. Use TaskCreate:
   - subject: "Get implementation plan from Codex"
   - description: "Request plan, wait for completion, process response"
   - activeForm: "Getting plan from Codex"
3. Use TaskUpdate to set status to `in_progress`

This call starts **Thread A** (read-only). Thread A is continued for the exchange (Step 5a) and the review fallback (Step 7/8).

**1. Prepare prompt file:**
```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_PROMPT="$TMP_DIR/codex-plan-prompt.txt"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$CODEX_PROMPT" << EOF
${LANG_DIRECTIVE}You are collaborating with Claude Code. Your role is to create a detailed implementation plan.

**IMPORTANT**: If you reference any files, always re-read them from disk even if you have read them before in this session. Ignore any cached content from earlier in this conversation.

## Task
[Task description]

## Context
[Relevant code context]

## Required Output

### 1. Files to Modify
List each file with type of change (create/modify/delete)

### 2. Implementation Steps
Numbered steps in execution order

### 3. Risk Assessment
Potential issues and edge cases

### 4. Test Considerations
What should be tested

## Response Format

At the end of your response, include a metadata block:

\`\`\`
---
status: continue or stop
open_questions:  # if any clarification needed
  - question 1
decisions:  # key decisions made
  - decision 1
---
\`\`\`

Use \`status: continue\` if you have questions, \`status: stop\` if the plan is complete.

Provide your plan now.
EOF
```

**2. Run Codex (new Thread A):**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-REPLACE"   # value printed in Step 0a
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
CODEX_PROMPT="$TMP_DIR/codex-plan-prompt.txt"
CODEX_OUTPUT="$TMP_DIR/codex-plan-output.md"
SANDBOX="${SANDBOX_SETTING:-read-only}"
MODEL="${MODEL_SETTING:-}"

rc=0
THREAD_A=$(codex_run_exec_session "$CODEX_PROMPT" "$CODEX_OUTPUT" "$SANDBOX" "$MODEL") || rc=$?
echo "codex rc=$rc thread=$THREAD_A"
if [ "$rc" -eq 0 ]; then
  codex_save_session_state "$TASK_ID" "exec" "$THREAD_A" "$SANDBOX" "codex-leads" > /dev/null
  echo "Codex plan saved to: $CODEX_OUTPUT"
fi
```

Handle `rc` per the **Codex Call Protocol** (new thread, so rc=3 cannot occur).

> **Important:** Set the Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds. Example: for 180s wait, use `timeout: 240000`. Max: 600000ms (10 minutes).
> For long-running tasks, use `run_in_background: true` on the Bash tool.

**Options based on settings:**
- `model` setting → passed as the `MODEL` argument (omit/empty when unset — Codex uses its own default)
- `sandbox` setting → `SANDBOX` argument (read-only | workspace-write | danger-full-access)

### Step 5: Read and Process Response

**Task transition:**
1. Mark "Get implementation plan from Codex" as `completed`
2. Use TaskCreate:
   - subject: "Review and approve plan"
   - description: "Validate plan completeness, present to user for approval"
   - activeForm: "Reviewing plan"
3. Use TaskUpdate to set status to `in_progress`

Once completion is detected:

1. Read the output file: `cat "$CODEX_OUTPUT"`
2. Parse the YAML response from Codex
3. Check `next_action` field (evaluated first, takes precedence):
   - If `next_action: continue` or `type: action_request` → Go to Step 5a (Discussion Loop)
   - If `next_action: stop` → Continue to Step 6
   - If `next_action` is missing → Default to `stop` for task_card/review, `continue` for action_request
4. Validate for completeness:
   - [ ] Files to modify are clearly listed
   - [ ] Steps are specific and actionable
   - [ ] Risks are identified

Present the plan to the user and wait for confirmation before implementing.

### Step 5a: Multi-turn Exchange Loop (Optional)

If Codex requests clarification or wants to continue the exchange:

**0. Check if exchange is enabled:**
- If `exchange.enabled: false` → Skip this step, proceed to Step 6

**1. Track exchange state:**
- Increment round counter
- Check if round < exchange.max_iterations (default: 3)

**2. Continue Thread A with `codex exec resume`:**

Thread A retains the whole conversation, so the prompt contains **only the new message**:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-REPLACE"   # value printed in Step 0a
ROUND="1"                  # exchange round number
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
EXCHANGE_PROMPT="$TMP_DIR/codex-exchange-prompt.txt"
CODEX_OUTPUT="$TMP_DIR/codex-plan-output.md"
SANDBOX="${SANDBOX_SETTING:-read-only}"
MODEL="${MODEL_SETTING:-}"

# Keep the previous response: CODEX_OUTPUT is cleared before the next turn,
# and a History Reconstruction needs it. History is scoped to this task.
HISTORY_DIR="$TMP_DIR/codex-history/$TASK_ID"
history_ok=1
if [ -s "$CODEX_OUTPUT" ]; then
  if ! mkdir -p "$HISTORY_DIR" || ! cp "$CODEX_OUTPUT" "$HISTORY_DIR/plan-round-${ROUND}.md"; then
    history_ok=0
  fi
fi

cat > "$EXCHANGE_PROMPT" << 'EOF'
[Your response to Codex's question/request]

Please respond with next_action: stop when the plan is complete.
EOF

load_rc=0
THREAD_A=$(codex_load_session_thread "$TASK_ID" "$SANDBOX") || load_rc=$?
if [ "$history_ok" -ne 1 ]; then
  # Do not start a turn that would delete the only copy of the previous response
  echo "HISTORY_SAVE_FAILED ($HISTORY_DIR)"
elif [ "$load_rc" -eq 2 ]; then
  echo "STATE_IO_ERROR"
elif [ "$load_rc" -eq 1 ]; then
  echo "NO_RESUMABLE_THREAD"
else
  rc=0
  NEW_ID=$(codex_run_exec_session "$EXCHANGE_PROMPT" "$CODEX_OUTPUT" "$SANDBOX" "$MODEL" "$THREAD_A") || rc=$?
  echo "codex rc=$rc thread=$NEW_ID"
  if [ "$rc" -eq 0 ]; then
    codex_save_session_state "$TASK_ID" "exec" "$NEW_ID" "$SANDBOX" "codex-leads" > /dev/null
  fi
fi
```

- `rc=0` → read `$CODEX_OUTPUT`, return to Step 5.
- `NO_RESUMABLE_THREAD` (no Thread A, legacy state, or sandbox changed) or `rc=3` (Thread A is gone) → overwrite `$EXCHANGE_PROMPT` with a **History Reconstruction** (task, context, the responses saved in `tmp/codex-history/$TASK_ID/plan-round-*.md` for **this task only**, and this round's message) and run the same `codex_run_exec_session` call **once** with an empty thread id; on `rc=0` save the new id with `codex_save_session_state "$TASK_ID" "exec" "$NEW_ID" "$SANDBOX" "codex-leads"`.
- `HISTORY_SAVE_FAILED` → stop and report (Codex was not called, so the previous response is still in `$CODEX_OUTPUT`).
- `rc=4/5`, `STATE_IO_ERROR` → follow the **Codex Call Protocol** (no automatic retry).

**3. User confirmation (based on exchange.user_confirm setting):**
- `never`: Fully automatic exchange
- `always`: Confirm each round
- `on_important` (default): Confirm only for major decisions

**4. Force stop conditions:**
- round >= exchange.max_iterations → Summarize and proceed
- Repeated same question → Ask user for direction

### Step 6: Implement

**Task transition:**
1. Mark "Review and approve plan" as `completed`
2. Use TaskCreate:
   - subject: "Implement changes"
   - description: "Execute plan step by step, track modifications"
   - activeForm: "Implementing changes"
3. Use TaskUpdate to set status to `in_progress`

Execute the plan step by step:
1. Make changes as specified
2. Track all modifications
3. Prepare diff summary for review

### Step 7: Request Review from Codex

**Task transition:**
1. Mark "Implement changes" as `completed`
2. Use TaskCreate:
   - subject: "Request review from Codex"
   - description: "Stage changes, request review, process feedback"
   - activeForm: "Getting review from Codex"
3. Use TaskUpdate to set status to `in_progress`

**0. Stage changes for Codex visibility (important!):**
```bash
export CODEX_SKILL_CONTEXT=1
git add -A
```
> **Why?** Staging ensures all changes are visible to Codex regardless of its file discovery method.
> This is staging only, not a commit. Run `git reset` after review to unstage if needed.

**1. Run review using `codex review` (primary) with a Thread A fallback:**

- **Primary:** `codex review --uncommitted` (`codex_run_review`) collects the diff natively. It runs as its own stateless session.
- **Fallback:** if it fails, continue **Thread A** (which already holds the plan) with a review prompt that points to a diff file. If Thread A is unavailable (load rc=1) start a new read-only session and include the plan in the prompt.

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-REPLACE"   # value printed in Step 0a
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_REVIEW="$TMP_DIR/codex-review-output.md"
MODEL="${MODEL_SETTING:-}"
SANDBOX="${SANDBOX_SETTING:-read-only}"
LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

# Primary: codex review --uncommitted
# Note: codex review --uncommitted does not accept a custom prompt.
# Custom review instructions are provided via the fallback path.
REVIEW_EXIT=0
codex_run_review "$CODEX_REVIEW" "$MODEL" || REVIEW_EXIT=$?

if [ "$REVIEW_EXIT" -ne 0 ]; then
  echo "codex review failed (exit=$REVIEW_EXIT), falling back to Thread A..."

  REVIEW_PROMPT="$TMP_DIR/codex-review-prompt.txt"
  DIFF_FILE="$TMP_DIR/codex-review-diff.txt"
  git diff --cached > "$DIFF_FILE"
  DIFF_FILE_ABS="$(cd "$(dirname "$DIFF_FILE")" && pwd)/$(basename "$DIFF_FILE")"

  cat > "$REVIEW_PROMPT" << EOF
${LANG_DIRECTIVE}Review the implementation of the plan we agreed on in this conversation.
(If this conversation has no plan, the plan is: [Plan from Step 3])

## Changes Made

The diff is saved in the following file. Please read it:
\`\`\`
$DIFF_FILE_ABS
\`\`\`

If you cannot access the file, respond with:
\`\`\`
---
status: stop
verdict: conditional
message: Unable to access diff file
---
\`\`\`

## Review Request

### 1. Alignment Check
Does implementation match the plan?

### 2. Code Quality
Rate readability and maintainability

### 3. Bugs and Issues
List any problems found. Mark with [P1] (critical), [P2] (high), [P3] (medium), [P4] (low).

### 4. Security Check
Any vulnerabilities?

### 5. Verdict
- PASS: No critical issues
- CONDITIONAL: Acceptable with improvements
- FAIL: Critical issues found

## Response Format

At the end of your response, include a metadata block:

\`\`\`
---
status: stop
verdict: pass / conditional / fail
findings:  # if any issues found
  - severity: low / medium / high
    message: description of issue
---
\`\`\`

Provide your review now.
EOF

  load_rc=0
  THREAD_A=$(codex_load_session_thread "$TASK_ID" "$SANDBOX") || load_rc=$?
  if [ "$load_rc" -eq 2 ]; then
    echo "STATE_IO_ERROR"
  else
    if [ "$load_rc" -ne 0 ]; then
      # No resumable Thread A: the prompt's "[Plan from Step 3]" placeholder must be filled
      THREAD_A=""
      echo "NO_RESUMABLE_THREAD (include the plan in the review prompt)"
    fi
    rc=0
    NEW_ID=$(codex_run_exec_session "$REVIEW_PROMPT" "$CODEX_REVIEW" "$SANDBOX" "$MODEL" "$THREAD_A") || rc=$?
    echo "codex rc=$rc thread=$NEW_ID"
    if [ "$rc" -eq 0 ]; then
      codex_save_session_state "$TASK_ID" "exec" "$NEW_ID" "$SANDBOX" "codex-leads" > /dev/null
    fi
  fi
fi

echo "Codex review saved to: $CODEX_REVIEW"
```

Handle the fallback `rc` per the **Codex Call Protocol** (rc=3 → rebuild with the plan and this review prompt in a new session, once).

### Step 8: Handle Review Result

**CRITICAL: Always iterate until PASS is received or max iterations reached.**

Claude must NOT give up after a single review response. The review loop should continue until:
- Verdict is `pass`
- Max iterations reached (default: 5)
- User explicitly requests to stop

**8.0 Parse verdict from response:**

Use `codex_infer_verdict()` for unified verdict parsing:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers (same loading pattern as Step 7)
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
CODEX_REVIEW="$TMP_DIR/codex-review-output.md"

REVIEW_RESPONSE=$(cat "$CODEX_REVIEW")

# Unified verdict inference: metadata → [P1]-[P4] → no-findings pass
VERDICT=$(codex_infer_verdict "$REVIEW_RESPONSE") || true

# Extract findings for fix iteration
FINDINGS=$(codex_extract_review_findings "$REVIEW_RESPONSE")

echo "Detected verdict: $VERDICT"
if [ -n "$FINDINGS" ]; then
  echo "Findings:"
  echo "$FINDINGS"
fi
```

**Re-review after fixes:** run Step 7 again. When the fallback path is used, Thread A still holds the previous review, so the fallback prompt can be shortened to:

```
I've applied the following fixes based on your review:
[description of fixes]

The updated diff is in: [diff file path]

Please re-review. Provide verdict: pass / conditional / fail.
```

**8.1 If verdict is missing or unclear:**

1. **Check for file access failure (fallback path only):**
   - If response contains "Unable to access diff file" → Retry with embedded diff

2. **Retry with embedded diff** (fallback for file access failure):
   ```bash
   DIFF_FILE="$TMP_DIR/codex-review-diff.txt"
   DIFF_CONTENT=$(cat "$DIFF_FILE")
   REVIEW_PROMPT="$TMP_DIR/codex-review-prompt.txt"
   cat > "$REVIEW_PROMPT" << EOF
   前回、差分ファイルにアクセスできなかったようです。
   差分を直接含めて再度レビューをお願いします。

   ## 差分

   \`\`\`diff
   ${DIFF_CONTENT}
   \`\`\`

   Mark findings with [P1] (critical), [P2] (high), [P3] (medium), [P4] (low).
   verdict: pass / conditional / fail で回答してください。
   EOF
   ```
   Send it on Thread A with `codex_run_exec_session` (Codex Call Protocol).

3. **Retry with simplified prompt** (up to 3 retries)

4. **If still no verdict after retries:**
   - Treat as `conditional` and continue to 8.3

**8.2 If PASS:**

Report completion to user with summary. Task complete.

**8.3 If CONDITIONAL:**

1. If specific findings (from `codex_extract_review_findings()`) → Apply fixes and re-request review
2. If no specific issues → Re-review with clarification
3. Continue iteration until pass or max iterations

**8.4 If FAIL:**

1. Extract specific issues from findings
2. Apply fixes based on Codex's feedback
3. Stage changes: `git add -A`
4. Re-request review with updated diff
5. Return to Step 8

**8a. Review Iteration Loop (Full Implementation):**

```
review_round = 0
max_rounds = review.max_iterations (default: 5)
verdict_retries = 0
max_verdict_retries = 3

WHILE review_round < max_rounds:
  review_round++

  1. Stage changes: git add -A
  2. Run review:
     a. Try codex_run_review() (primary)
     b. If non-zero exit → fallback: codex_run_exec_session() on Thread A with diff file prompt
        (rc handling per Codex Call Protocol; only rc=3 is rebuilt automatically)
     c. Parse verdict via codex_infer_verdict()
     d. Extract findings via codex_extract_review_findings()

  IF fallback path AND response contains "Unable to access diff file":
    Rebuild prompt with diff content embedded
    review_round--
    CONTINUE

  IF verdict is empty (unable to determine):
    verdict_retries++
    IF verdict_retries < max_verdict_retries:
      Send follow-up asking for explicit verdict (Thread A resume)
      CONTINUE
    ELSE:
      verdict = "conditional" (fallback)

  IF verdict == "pass":
    BREAK → Success

  IF verdict == "conditional":
    IF specific_findings_exist:
      Apply fixes
    ELSE:
      Re-request with clarification
    CONTINUE

  IF verdict == "fail":
    Apply fixes based on findings
    CONTINUE

IF review_round >= max_rounds AND verdict != "pass":
  Report: "Max review iterations reached. Final verdict: {verdict}"
  Ask user if they want to continue or accept current state
```

**User confirmation (based on review.user_confirm setting):**
- `never` (default): Auto-iterate without confirmation
- `always`: Confirm each round
- `on_important`: Confirm only for high-severity findings

### Step 9: Cleanup

**Task transition:**
1. Mark "Request review from Codex" as `completed`
2. Report completion to user

Remove temporary files (event logs `*.jsonl` / `*.stderr.log` are written next to each output file):
```bash
export CODEX_SKILL_CONTEXT=1
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
rm -f "$TMP_DIR/codex-plan-output.md" "$TMP_DIR/codex-plan-prompt.txt" "$TMP_DIR/codex-exchange-prompt.txt"
rm -f "$TMP_DIR/codex-plan-output.jsonl" "$TMP_DIR/codex-plan-output.stderr.log"
rm -rf "$TMP_DIR/codex-history/${TASK_ID:-collab-REPLACE}"   # this task's exchange history only
rm -f "$TMP_DIR/codex-review-output.md" "$TMP_DIR/codex-review-prompt.txt"
rm -f "$TMP_DIR/codex-review-output.jsonl" "$TMP_DIR/codex-review-output.stderr.log"
rm -f "$TMP_DIR/codex-review-diff.txt"
```

---

## Claude-Leads Workflow (新規ワークフロー)

> This workflow has **Claude plan and review, Codex implement**.
> Active only when `workflow` is explicitly set to `claude-leads`.
>
> **Key difference**: Codex runs with `workspace-write` sandbox to make file changes directly.

**Responsibility Boundary:**
| Role | Responsibility |
|------|---------------|
| **Claude** | Quality gate: deep analysis, planning, review, approval |
| **Codex** | Execution engine: accurate implementation per plan |
| **User** | Final approval: plan approval and ultimate decision authority |

> Claude bears responsibility for plan quality and review thoroughness. Codex bears responsibility for faithful execution. The user has final say at the plan approval step (Step 5c).

### Step 2c: Deep Codebase Analysis (Claude)

**Create a task to track progress:**

Use TaskCreate:
- subject: "Deep codebase analysis for planning"
- description: "Analyze codebase, identify affected files, understand architecture"
- activeForm: "Analyzing codebase"

Then use TaskUpdate to set status to `in_progress`.

**Perform deep analysis:**

Claude should thoroughly analyze the codebase using Read, Glob, and Grep:

1. **Understand the task**: Parse the core objective from the task description
2. **Map affected files**: Use Glob and Grep to find all relevant files
3. **Read key files**: Read each affected file to understand current implementation
4. **Understand dependencies**: Trace imports, function calls, and data flow
5. **Check existing tests**: Find related test files and understand test patterns
6. **Review recent changes**: Use `git log` to understand recent context

### Step 3c: Create Detailed Implementation Plan (Claude)

**Task transition:**
1. Mark "Deep codebase analysis for planning" as `completed`
2. Use TaskCreate:
   - subject: "Create implementation plan"
   - description: "Design detailed step-by-step plan based on analysis"
   - activeForm: "Creating plan"
3. Use TaskUpdate to set status to `in_progress`

Based on the analysis, create a detailed implementation plan that includes:

1. **Files to Modify**: List each file with type of change (create/modify/delete)
2. **Implementation Steps**: Numbered steps in execution order with specific code changes
3. **Risk Assessment**: Potential issues and edge cases
4. **Test Considerations**: What should be tested

### Step 4c: Plan Consultation with Codex (Optional)

> This step is optional and controlled by `claude_leads.consult_codex` setting (default: true).
> Skip this step if `consult_codex: false`.

**Purpose:** Get Codex's perspective on the plan before implementation.

This call creates **Thread B** (read-only), saved as a named thread together with its sandbox.

**1. Prepare consultation prompt:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CONSULT_PROMPT="$TMP_DIR/codex-consult-prompt.txt"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$CONSULT_PROMPT" << EOF
${LANG_DIRECTIVE}You are reviewing an implementation plan created by Claude Code before execution.

**IMPORTANT**: If you reference any files, always re-read them from disk.

## Task
[Task description]

## Proposed Plan
[Claude's implementation plan from Step 3c]

## Review Request

Please review this plan and provide feedback on:

### 1. Feasibility
Can this plan be executed as-is? Any missing steps?

### 2. Risks
Any risks or edge cases not covered?

### 3. Improvements
Suggestions for better approach or optimization?

### 4. Verdict
- APPROVE: Plan is solid, proceed with implementation
- SUGGEST: Plan is acceptable with suggested improvements
- RETHINK: Significant issues, plan needs revision

## Response Format

At the end of your response, include a metadata block:

\`\`\`
---
status: stop
verdict: approve / suggest / rethink
suggestions:
  - suggestion 1
---
\`\`\`

Provide your review now.
EOF
```

**2. Run Codex consultation (Thread B):**

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-REPLACE"   # value printed in Step 0a
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
CONSULT_PROMPT="$TMP_DIR/codex-consult-prompt.txt"
CONSULT_OUTPUT="$TMP_DIR/codex-consult-output.md"
SANDBOX="read-only"
MODEL="${MODEL_SETTING:-}"

# Re-consultation continues Thread B if it exists with the same sandbox
# (rc=1 or sandbox mismatch → new thread, rc=2 → stop)
load_rc=0
THREAD_B=$(codex_load_thread "$TASK_ID" "threadB") || load_rc=$?
sandbox_rc=0
SANDBOX_B=$(codex_load_thread_sandbox "$TASK_ID" "threadB") || sandbox_rc=$?
if [ "$load_rc" -eq 2 ] || [ "$sandbox_rc" -eq 2 ]; then
  echo "STATE_IO_ERROR"
else
  if [ "$load_rc" -ne 0 ] || [ "$SANDBOX_B" != "$SANDBOX" ]; then
    THREAD_B=""
  fi
  rc=0
  NEW_ID=$(codex_run_exec_session "$CONSULT_PROMPT" "$CONSULT_OUTPUT" "$SANDBOX" "$MODEL" "$THREAD_B") || rc=$?
  echo "codex rc=$rc thread=$NEW_ID"
  if [ "$rc" -eq 0 ]; then
    codex_save_thread_session "$TASK_ID" "threadB" "$NEW_ID" "$SANDBOX"
    echo "Codex consultation saved to: $CONSULT_OUTPUT"
  fi
fi
```

Handle `rc` per the **Codex Call Protocol**.

**3. Process Codex's feedback:**

- If `verdict: approve` → Proceed to Step 5c
- If `verdict: suggest` → Incorporate suggestions into the plan, proceed to Step 5c
- If `verdict: rethink` → Revise plan based on feedback, optionally re-consult (Thread B is resumed)

### Step 5c: User Approval

**Task transition:**
1. Mark "Create implementation plan" as `completed`
2. Use TaskCreate:
   - subject: "Get user approval for plan"
   - description: "Present plan (with Codex feedback if available) for user approval"
   - activeForm: "Waiting for user approval"
3. Use TaskUpdate to set status to `in_progress`

Present the plan to the user, including Codex's feedback if consultation was performed.

Use AskUserQuestion to get user approval:
- Show the plan summary
- If Codex suggested improvements, highlight them
- Ask user to approve, modify, or reject the plan

**If user approves** → Continue to Step 6c
**If user requests modifications** → Update plan and re-present
**If user rejects** → End workflow

### Step 6c: Safety Checkpoint

**Before Codex makes any changes, save the current state.**

Based on `claude_leads.safety_checkpoint` setting:

**`stash` (default):**
```bash
export CODEX_SKILL_CONTEXT=1
git stash push -m "codex-collab: pre-implementation checkpoint $(date +%Y%m%d-%H%M%S)"
echo "Safety checkpoint created (git stash)"
```

**`wip-commit`:**
```bash
export CODEX_SKILL_CONTEXT=1
git add -A
git commit -m "WIP: codex-collab pre-implementation checkpoint" --allow-empty
echo "Safety checkpoint created (WIP commit)"
```

**`none`:**
- Skip checkpoint (user accepts risk)

### Step 7c: Codex Implementation

**Task transition:**
1. Mark "Get user approval for plan" as `completed`
2. Use TaskCreate:
   - subject: "Codex implements changes"
   - description: "Send plan to Codex with workspace-write sandbox, monitor implementation"
   - activeForm: "Codex implementing"
3. Use TaskUpdate to set status to `in_progress`

This call creates **Thread C** (workspace-write). It is always a separate thread from Thread B (one thread = one sandbox).

**1. Prepare implementation prompt:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
IMPL_PROMPT="$TMP_DIR/codex-impl-prompt.txt"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$IMPL_PROMPT" << EOF
${LANG_DIRECTIVE}You are implementing changes based on a plan created by Claude Code.

**IMPORTANT**: Execute the plan exactly as specified. If you encounter issues, describe them clearly.

## Task
[Task description]

## Implementation Plan
[Detailed plan from Step 3c, with any modifications from consultation/user feedback]

## Instructions

1. Implement each step in order
2. Create/modify/delete files as specified
3. Follow existing code style and patterns
4. Do NOT skip any steps

## Response Format

After implementation, include a metadata block:

\`\`\`
---
status: stop
files_changed:
  - path/to/file1.ts (modified)
  - path/to/file2.ts (created)
issues:
  - description of any issues encountered
---
\`\`\`

Begin implementation now.
EOF
```

**2. Run Codex implementation (new Thread C):**

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-REPLACE"   # value printed in Step 0a
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
IMPL_PROMPT="$TMP_DIR/codex-impl-prompt.txt"
IMPL_OUTPUT="$TMP_DIR/codex-impl-output.md"
SANDBOX="${CLAUDE_LEADS_SANDBOX:-workspace-write}"
MODEL="${MODEL_SETTING:-}"

rc=0
THREAD_C=$(codex_run_exec_session "$IMPL_PROMPT" "$IMPL_OUTPUT" "$SANDBOX" "$MODEL") || rc=$?
echo "codex rc=$rc thread=$THREAD_C"
if [ "$rc" -eq 0 ]; then
  codex_save_thread_session "$TASK_ID" "threadC" "$THREAD_C" "$SANDBOX"
  echo "Codex implementation saved to: $IMPL_OUTPUT"
fi
```

> **Important:** The sandbox is set to `workspace-write` (configurable via `claude_leads.sandbox`). This allows Codex to create and modify files within the project directory.
> **rc=4/5 here may mean files were already changed.** Run `git status` and `git diff --stat` before asking the user whether to retry, restore the safety checkpoint, or continue manually. Never re-run the implementation automatically.

### Step 8c: Claude Review

**Task transition:**
1. Mark "Codex implements changes" as `completed`
2. Use TaskCreate:
   - subject: "Review Codex's implementation"
   - description: "Review changes via git diff and file reading, verify correctness"
   - activeForm: "Reviewing implementation"
3. Use TaskUpdate to set status to `in_progress`

**Claude reviews the changes made by Codex:**

1. **Check git diff:**
```bash
export CODEX_SKILL_CONTEXT=1
git diff
git diff --stat
```

2. **CRITICAL: Plan-vs-diff validation (mandatory):**
   Compare `git diff --stat` output against the file list in the implementation plan (Step 3c).
   - If files **outside the plan** are modified → **immediately halt** and report to user
   - Ask user whether to: (a) accept the extra changes, (b) revert them, or (c) abort entirely

3. **Read modified files:** Use Read tool to examine each changed file
4. **Verify against plan:** Check that each step was implemented correctly
5. **Check for issues:**
   - Code quality and style consistency
   - Security vulnerabilities
   - Missing error handling
   - Test coverage gaps
6. **Run lint/test if available**

### Step 9c: Fix Iteration & Completion

**Review iteration loop (Claude-led):**

```
review_round = 0
max_rounds = claude_leads.review.max_iterations (default: 3)

WHILE review_round < max_rounds:
  review_round++

  1. Claude reviews changes (git diff + Read)
  2. IF issues found:
     a. Prepare fix instructions for Codex (fix prompt below)
     b. Resume Thread C (Codex keeps the implementation context):
          THREAD_C=$(codex_load_thread "$TASK_ID" "threadC")            # rc=1 → new thread, rc=2 → stop
          SANDBOX_C=$(codex_load_thread_sandbox "$TASK_ID" "threadC")   # must be workspace-write
          codex_run_exec_session fix_prompt output "$SANDBOX_C" "$MODEL" "$THREAD_C"
        rc=3 → rebuild (plan + current git diff + fix instructions) in a new workspace-write thread once
        rc=4/5 → git status / git diff --stat, then ask the user (no automatic retry)
     c. CONTINUE (re-review)
  3. IF no issues:
     BREAK → Success

IF review_round >= max_rounds AND issues remain:
  Report: "Max review iterations reached. Remaining issues:"
  List remaining issues
  Ask user for direction
```

**Fix prompt and Thread C resume:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-REPLACE"   # value printed in Step 0a
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
FIX_PROMPT="$TMP_DIR/codex-fix-prompt.txt"
FIX_OUTPUT="$TMP_DIR/codex-fix-output.md"
MODEL="${MODEL_SETTING:-}"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$FIX_PROMPT" << EOF
${LANG_DIRECTIVE}Fix the following issues found during review.

## Issues to Fix
[List of specific issues with file paths and line numbers]

## Instructions
1. Fix each issue as described
2. Do not change anything else
3. Preserve existing code style

## Response Format
\`\`\`
---
status: stop
fixes_applied:
  - description of fix 1
  - description of fix 2
---
\`\`\`
EOF

load_rc=0
THREAD_C=$(codex_load_thread "$TASK_ID" "threadC") || load_rc=$?
sandbox_rc=0
SANDBOX_C=$(codex_load_thread_sandbox "$TASK_ID" "threadC") || sandbox_rc=$?
if [ "$load_rc" -eq 2 ] || [ "$sandbox_rc" -eq 2 ]; then
  echo "STATE_IO_ERROR"
elif [ "$load_rc" -ne 0 ] || [ "$SANDBOX_C" != "workspace-write" ]; then
  echo "THREAD_C_UNAVAILABLE (start a new workspace-write thread with plan + git diff + fix instructions)"
else
  rc=0
  NEW_ID=$(codex_run_exec_session "$FIX_PROMPT" "$FIX_OUTPUT" "$SANDBOX_C" "$MODEL" "$THREAD_C") || rc=$?
  echo "codex rc=$rc thread=$NEW_ID"
fi
```

**Handle the fix result before anything else:**

| Result | Action |
|--------|--------|
| `rc=0` | Read `$FIX_OUTPUT`, then **re-review** (back to the top of the loop: `git diff` + Read). Never mark the review completed directly from `rc=0`. |
| `THREAD_C_UNAVAILABLE` / `rc=3` | Start a new workspace-write thread **once** with plan + current `git diff` + fix instructions; save it with `codex_save_thread_session "$TASK_ID" "threadC" "$NEW_ID" "workspace-write"`. Then re-review. |
| `rc=4` / `rc=5` | Files may be partially changed. Run `git status` and `git diff --stat`, show the tail of `tmp/codex-fix-output.stderr.log`, and ask the user (retry / restore the safety checkpoint / fix manually). **Do not proceed to Completion and do not delete the logs.** |
| `STATE_IO_ERROR` | Stop and report. |

**Completion** (only when the latest re-review found no issues):

1. Mark "Review Codex's implementation" as `completed`
2. **Cleanup temporary files:**
```bash
export CODEX_SKILL_CONTEXT=1
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
rm -f "$TMP_DIR/codex-consult-prompt.txt" "$TMP_DIR/codex-consult-output.md"
rm -f "$TMP_DIR/codex-consult-output.jsonl" "$TMP_DIR/codex-consult-output.stderr.log"
rm -f "$TMP_DIR/codex-impl-prompt.txt" "$TMP_DIR/codex-impl-output.md"
rm -f "$TMP_DIR/codex-impl-output.jsonl" "$TMP_DIR/codex-impl-output.stderr.log"
rm -f "$TMP_DIR/codex-fix-prompt.txt" "$TMP_DIR/codex-fix-output.md"
rm -f "$TMP_DIR/codex-fix-output.jsonl" "$TMP_DIR/codex-fix-output.stderr.log"
```
3. Report completion to user with summary of changes

---

## Error Handling

If `codex` command is not available:
- Inform user: "Codex CLI is not installed or not in PATH. Would you like to proceed with Claude-only mode?"
- If yes, continue without Codex planning/review

If Codex returns an error:
- Report the error from the output file
- Offer to retry or proceed manually

If timeout (`codex.wait_timeout`, default 180s) without completion:
1. **Check Codex status** - Is Codex still running?
2. **If still running** → Re-run with extended timeout (up to max 600000ms)
3. **If completed but no output** → Read partial output and report to user
4. **If Codex failed** → Report error and offer to retry or proceed manually

## Notes

- **Architecture**: Codex is driven only through the `codex` CLI. `codex mcp-server` was removed in codex-cli 0.154.0 (verified on 0.154.0; supported: 0.154.0+).
  - **Stateful turns**: `codex_run_exec_session` runs `codex exec --json -o <output>` for a new thread and `codex exec -s <sandbox> resume <thread_id> --json -o <output>` to continue. The thread id is taken from the `thread.started` event and persisted in session state.
  - **Review**: `codex review --uncommitted` (`codex_run_review`) is a separate stateless session; its fallback continues Thread A.
  - **Response body**: always read from the `-o` output file. JSONL (`*.jsonl`) and stderr (`*.stderr.log`) are written next to it for diagnostics.
- **Thread topology**:
  - codex-leads: Thread A (plan → exchange → review fallback, read-only), saved as `threadId`
  - claude-leads: Thread B (consultation, read-only) and Thread C (implementation → fixes, workspace-write), saved via `codex_save_thread_session` as `"<uuid>|<sandbox>"`
  - One thread = one sandbox; `--last` and `--ephemeral` are never used.
- **Failure handling**: see **Codex Call Protocol**. Only rc=3 (thread not found before the turn started) is rebuilt automatically, once. rc=4/5 are never retried automatically.
- **Session state**: `tmp/codex-session-{task_id}.json` stores mode (`exec`), threadId, threads, sandbox, workflow. Legacy files written by MCP-era versions (mode `mcp`/`bash`) are migrated on load and their thread ids are discarded.
- **Workflow modes**:
  - **codex-leads**: Traditional workflow. Codex plans/reviews, Claude implements. Uses `read-only` sandbox by default.
  - **claude-leads**: New workflow. Claude plans/reviews, Codex implements. Uses `workspace-write` sandbox by default.
  - **auto**: 常に `codex-leads` を選択。`claude-leads` は明示的に `workflow: claude-leads` を指定した場合のみ有効。
- Output files are saved in project's `tmp/` directory. This directory is excluded by `.gitignore`.
- **Important**: Stage changes with `git add -A` before review so Codex can see new files
- **Multi-turn exchange** (codex-leads only): Use `next_action: continue|stop` to control exchange flow. Each round resumes Thread A with only the new message.
- **Review iteration** (codex-leads): Continue iterating until `pass` or max iterations (default: 5).
- **Claude-led review** (claude-leads): Claude reviews via `git diff` + Read. Max iterations controlled by `claude_leads.review.max_iterations` (default: 3).
- **Safety checkpoint** (claude-leads): Before Codex implementation, save state via git stash (default).
- **Timeout configuration**: `codex.wait_timeout` (default: 180s, max: 600s) controls how long to wait for Codex. Set Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds.
- **Background execution**: For long-running Codex turns, use `run_in_background: true` on the Bash tool.

## Compact Recovery

If you've been compacted during this workflow:

1. Run `TaskList` to see current progress
2. Find the task with status `in_progress`
3. **Check session state** for the thread ids:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

# Find the most recent session state
ls -t tmp/codex-session-*.json 2>/dev/null | head -3
```

4. **Load threads** (this also migrates MCP-era state files):
   - codex-leads: `codex_load_session_thread "$TASK_ID" "read-only"` → prints Thread A (only when it was created with that sandbox)
   - claude-leads: `codex_load_thread "$TASK_ID" "threadB"` / `codex_load_thread "$TASK_ID" "threadC"` (+ `codex_load_thread_sandbox`)
   - load rc=1 (no thread / legacy value / sandbox mismatch) → the step starts a new thread with its own inputs
   - load rc=2 → stop and report (state I/O failure)
5. Resume the current step. A resumed call that returns rc=3 is rebuilt once (History Reconstruction); rc=4/5 go to the user.
6. If the step's output file already exists **and** its `.jsonl` contains `turn.completed`, the turn finished before compaction — read the output instead of re-running.
7. **Step 7c / 9c (workspace-write)**: if the `.jsonl` exists without `turn.completed`, the implementation may be partially applied. Run `git status` / `git diff --stat` and ask the user before re-running anything.

**Task to Step mapping (codex-leads):**
| Task | Resume at |
|------|-----------|
| "Analyze task and gather context" | Step 2 |
| "Get implementation plan from Codex" | Step 3 |
| "Review and approve plan" | Step 5 |
| "Implement changes" | Step 6 |
| "Request review from Codex" | Step 7 |

**Task to Step mapping (claude-leads):**
| Task | Resume at |
|------|-----------|
| "Deep codebase analysis for planning" | Step 2c |
| "Create implementation plan" | Step 3c |
| "Get user approval for plan" | Step 5c |
| "Codex implements changes" | Step 7c |
| "Review Codex's implementation" | Step 8c |

**Recovery example:**
```
TaskList shows:
- [completed] Analyze task and gather context
- [in_progress] Get implementation plan from Codex

→ tmp/codex-plan-output.jsonl contains turn.completed → proceed to Step 5
→ otherwise: threadId in session state?
    yes → resume it (codex_run_exec_session ... "$THREAD_A")
    no  → re-run Step 3 (new Thread A)
```
