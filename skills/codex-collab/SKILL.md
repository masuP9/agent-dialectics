---
name: Codex Collab
description: 'This skill should be used when the user asks to "collaborate with Codex", "use Codex for planning", "get Codex review", "delegate to Codex", "code review", "PR review", "review this code", "review this PR", "Codexと協調", "Codexにレビュー", "Codexに計画を作成させたい", "Codexに任せる", "Codexに委任", "Codexと連携", "Codexに相談", "Codexの意見", "Claude plans", "Claude-led", "Claudeが計画", "Claude主導", "Codexに実装させる", "Codexに実装を任せる", "Claudeがレビュー", "コードレビューして", "PRをレビューして", "コードをレビューして", "このコードをレビュー", or mentions coordinating tasks between Claude Code and Codex CLI. NOTE: This is the default skill for generic code/PR review requests. Use devils-advocate only when the user explicitly asks for adversarial/red-team critique of a design or proposal.'
---

# Codex Collaboration Skill

Coordinate tasks between Claude Code and OpenAI Codex CLI using adaptive workflow selection based on model strengths.

## Overview

This skill enables effective collaboration between two AI systems with **two workflow modes**:

**Codex-Leads (従来):**
- **Codex**: Planning, code review, architectural decisions
- **Claude Code**: Implementation, file operations, testing

**Claude-Leads (新規):**
- **Claude Code**: Deep analysis, planning, code review
- **Codex**: Fast implementation with workspace-write sandbox

デフォルト（`auto`）は常に **Codex-Leads** を選択。`claude-leads` は `workflow: claude-leads` を明示指定した場合のみ有効。

**通信方式**: `codex` CLI のみ（codex-cli 0.154.0 以上）。
- **ステートフル実行** (`codex_run_exec_session`): 新規は `codex exec --json -o <output>`、継続は `codex exec -s <sandbox> resume <thread_id> --json -o <output>`。thread id をセッション状態に保存して multi-turn を継続する。応答本文は `-o` の出力ファイルのみを正とする。
- **レビュー** (`codex_run_review`): `codex review --uncommitted`（独立したステートレスセッション）。
- **失敗の扱い**: 戻り値で分類する。`3`（再開対象スレッドが存在しない・ターン未開始）のみ自動で 1 回再構築、`4`/`5`（実行結果不明・結果不正）は自動再実行しない。

## Prerequisites

Before starting collaboration:
1. Verify `codex` CLI is available: `which codex` or `codex --version` (0.154.0+)
2. Check for project settings in `.claude/codex-collab.local.md`
3. If the CLI is not available, inform user and proceed with Claude-only mode

## Workflow: Review Type (Default)

### Phase 1: Task Analysis

When receiving a task for collaboration:

1. Parse the task description to identify:
   - Core objective
   - Affected files/components
   - Complexity level
   - Required context

2. Gather relevant context:
   - Read related files
   - Check existing tests
   - Review recent changes

### Phase 2: Request Plan from Codex

```bash
export CODEX_SKILL_CONTEXT=1
source scripts/codex-helpers.sh
PROMPT_FILE=$(codex_write_prompt "$PLANNING_PROMPT" "plan")
OUTPUT_FILE="$(codex_tmp_path 'codex-plan-output.md')"
rc=0
THREAD_ID=$(codex_run_exec_session "$PROMPT_FILE" "$OUTPUT_FILE" "read-only" "") || rc=$?
# rc=0 → save THREAD_ID (codex_save_session_state) for the exchange and review fallback
```

Read results from the output file.

### Phase 3: Implement Based on Plan

After receiving Codex's plan:

1. Validate the plan is reasonable
2. Present plan to user for confirmation
3. Execute implementation step by step
4. Track changes made

### Phase 4: Request Review from Codex

After implementation:

1. **Stage changes for Codex visibility** (important!):
```bash
git add -A
git reset -- tmp/ 2>/dev/null || true
```
> **Why?** Staging ensures all changes are visible to Codex regardless of its file discovery method.

2. Run review (`codex review` primary, plan thread as fallback):

```bash
export CODEX_SKILL_CONTEXT=1
source scripts/codex-helpers.sh
REVIEW_OUTPUT="$(codex_tmp_path 'codex-review-output.md')"
codex_run_review "$REVIEW_OUTPUT" "$MODEL" || REVIEW_EXIT=$?

if [ "${REVIEW_EXIT:-0}" -ne 0 ]; then
  REVIEW_PROMPT_FILE=$(codex_write_prompt "$REVIEW_PROMPT" "review")
  # Resume the Phase 2 thread so Codex reviews against its own plan
  rc=0
  codex_run_exec_session "$REVIEW_PROMPT_FILE" "$REVIEW_OUTPUT" "read-only" "" "$THREAD_ID" > /dev/null || rc=$?
fi
```

3. Parse verdict and findings:
```bash
RESPONSE=$(cat "$REVIEW_OUTPUT")
VERDICT=$(codex_infer_verdict "$RESPONSE") || true
FINDINGS=$(codex_extract_review_findings "$RESPONSE")
```

The review uses `[P1]-[P4]` priority markers as the primary source for verdict inference:
- `[P1]`/`[P2]` → fail
- `[P3]`/`[P4]` → conditional
- No findings + sufficient output → pass
- Metadata block (`verdict: pass/conditional/fail`) is also supported as an alternative

### Phase 5: Handle Review Result

Based on review verdict:

**Pass**: Report completion to user

**Conditional**:
1. Apply suggested improvements
2. Re-request review if significant changes

**Fail**:
1. Analyze failure reasons
2. Either fix issues or escalate to user

## Settings and Configuration

### Reading Project Settings

Check for `.claude/codex-collab.local.md` in project root:

```markdown
---
sandbox: read-only
language: ja
---

# Project-specific instructions
```

Parse YAML frontmatter for:
- `model`: Codex model to use (omit to use the Codex default from `~/.codex/config.toml`)
- `sandbox`: read-only | workspace-write | danger-full-access
- `workflow`: Workflow mode (auto | codex-leads | claude-leads, default: auto; auto は常に codex-leads を選択)
- `exchange.enabled`: Enable planning exchange (default: true, codex-leads only)
- `exchange.max_iterations`: Maximum rounds for multi-turn exchange (default: 3)
- `exchange.user_confirm`: When to ask user confirmation (never | always | on_important)
- `exchange.history_mode`: How to rebuild history when a resumed thread is lost (full | summarize; used only for rc=3 — normally `codex exec resume` preserves history)
- `review.enabled`: Enable review iteration (default: true, codex-leads only)
- `review.max_iterations`: Maximum rounds for review iteration (default: 5)
- `review.max_verdict_retries`: Retries when verdict is missing/unclear (default: 3)
- `review.user_confirm`: When to ask user confirmation for reviews (default: never)
- `claude_leads.sandbox`: Sandbox for Codex implementation (default: workspace-write)
- `claude_leads.consult_codex`: Enable plan consultation phase (default: true)
- `claude_leads.safety_checkpoint`: Pre-implementation checkpoint (stash | wip-commit | none, default: stash)
- `claude_leads.review.max_iterations`: Max review-fix iterations (default: 3)
- `codex.wait_timeout`: Max execution time for a Codex turn in seconds (default: 180, max: 600)

### Settings Priority

Apply settings in this order (later overrides earlier):

1. **Safe defaults**: sandbox=read-only
2. **Global settings**: ~/.claude/codex-collab.local.md
3. **Project settings**: .claude/codex-collab.local.md
4. **Command arguments**: Explicit user request

### Safe Defaults

Always start with secure defaults:
- `workflow: auto` - 常に codex-leads を選択（claude-leads は明示指定時のみ）
- `sandbox: read-only` - Codex cannot modify files (codex-leads)
- `exchange.enabled: true` - Planning exchange enabled by default
- `exchange.max_iterations: 3` - Prevent runaway exchanges
- `exchange.user_confirm: on_important` - Ask user for major decisions
- `exchange.history_mode: summarize` - Efficient token usage
- `review.enabled: true` - Review iteration enabled by default
- `review.max_iterations: 5` - More iterations allowed (goal is clear, diff is small)
- `review.user_confirm: never` - Auto-iterate without confirmation
- `claude_leads.sandbox: workspace-write` - Codex can modify project files (claude-leads)
- `claude_leads.consult_codex: true` - Plan consultation enabled
- `claude_leads.safety_checkpoint: stash` - Git stash before implementation
- `claude_leads.review.max_iterations: 3` - Claude review iterations

## Quality Gates

### Plan Quality Criteria

A valid plan from Codex must include:
- [ ] Clear list of files to modify
- [ ] Specific changes for each file
- [ ] Rationale for approach
- [ ] Identified risks or concerns
- [ ] Test coverage considerations

If plan is incomplete, request clarification from Codex.

### Review Acceptance Criteria

Accept review as "Pass" only when:
- [ ] All changed files reviewed
- [ ] No critical bugs identified
- [ ] Security concerns addressed
- [ ] Design aligns with original plan
- [ ] Test coverage adequate

## Running Codex

### ステートフル実行パターン（codex exec + resume）

```bash
# ヘルパー関数を使用（推奨）
export CODEX_SKILL_CONTEXT=1
source scripts/codex-helpers.sh
PROMPT_FILE=$(codex_write_prompt "$PROMPT_CONTENT" "plan")
OUTPUT_FILE="$(codex_tmp_path 'codex-output.md')"

# 新規スレッド
rc=0
THREAD_ID=$(codex_run_exec_session "$PROMPT_FILE" "$OUTPUT_FILE" "read-only" "") || rc=$?

# 同一スレッドで継続（sandbox はスレッド作成時と同じにする）
rc=0
THREAD_ID=$(codex_run_exec_session "$NEXT_PROMPT_FILE" "$OUTPUT_FILE" "read-only" "" "$THREAD_ID") || rc=$?

# 直接実行する場合（-s は exec と resume の間。--last は使わない）
codex exec -s read-only --json -o output.md - < prompt.txt > events.jsonl
codex exec -s read-only resume "$THREAD_ID" --json -o output.md - < next.txt > events.jsonl
```

戻り値: `0` 成功（thread id を stdout に出力）/ `2` 前提エラー（codex 未起動）/ `3` 再開対象スレッドなし（自動で 1 回だけ再構築可）/ `4` 実行結果不明 / `5` 完了したが結果不正。`4`/`5` は自動再実行しない。

### ステートレス実行（単発）

```bash
codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" "read-only"
```

### Codex CLI Options

- `-m, --model <model>` - Specify model (e.g., gpt-5.6-sol; omit to use the Codex default)
- `-s, --sandbox <mode>` - read-only | workspace-write | danger-full-access
- `-C, --cd <dir>` - Working directory
- `--full-auto` - Automatic execution mode
- `-` - Read prompt from stdin

### Important Notes

- **Stateful sessions**: `codex_run_exec_session` persists context via the thread id from the `thread.started` event; `codex exec resume` continues it. Plain `codex_run_exec` calls are stateless.
- **One thread = one sandbox**: never resume a thread with a different sandbox; use a separate named thread (e.g. claude-leads Thread B = read-only, Thread C = workspace-write)
- Use `-s read-only` for planning/review tasks (Codex won't modify files)
- Use `-s workspace-write` for implementation tasks (claude-leads workflow)
- Response body comes from the `-o` output file; the stateless `codex_run_exec()` output may contain ANSI escape codes (stripped automatically)
- **Stdin input**: Use redirect format (`codex exec - < file`) for reliable input
- **Timeout**: Bash tool has max 600s (10 minutes) timeout.
- **Background agents**: Background subagents (`run_in_background: true`) require pre-approved Bash permissions in `~/.claude/settings.json` or `.claude/settings.json`. Without pre-approval, Bash tool calls are auto-denied because permission prompts are unavailable in background mode.

## Error Handling

### CLI Unavailable

If `codex` command is not found:
1. Inform user: "Codex CLI is not installed or not in PATH"
2. Offer to proceed with Claude-only mode
3. Continue with standard Claude Code workflow

### Codex Timeout or Error

If a Codex turn fails (`codex_run_exec_session` return code):
1. `3` (resumed thread not found) → rebuild the context from the role's inputs and retry once in a new thread
2. `4` / `5` → do **not** retry automatically: check `*.stderr.log` next to the output file (and `git status` for workspace-write), then ask the user
3. `2` → precondition error; fix and re-run, or proceed manually and inform user

### Bash Tool Timeout

Bash tool has max 600s (10 minutes) timeout. For long-running tasks:
1. Set appropriate `codex.wait_timeout` setting
2. Consider breaking tasks into smaller parts
3. Use `run_in_background: true` for background execution

## Structured Communication Protocol

This plugin uses a minimal protocol header to enable structured communication between Claude Code and Codex CLI.

### Protocol Header

Every prompt to Codex includes a ~15-line protocol header:

```yaml
## Protocol (codex-collab/v1)
format: yaml
rules:
  - respond with exactly one top-level YAML mapping
  - include required fields: type, id, status, body
  - if unsure or blocked, use type=action_request with clarifying questions
types:
  task_card: {body: title, context, requirements, acceptance_criteria, proposed_steps, risks, test_considerations}
  result_report: {body: summary, changes, tests, risks, checks}
  action_request: {body: question, options, expected_response}
  review: {body: verdict, summary, findings, suggestions}
status: [ok, partial, blocked]
verdict: [pass, conditional, fail]
severity: [low, medium, high]
next_action: [continue, stop]
```

### Message Types

| Type | Purpose | Used By |
|------|---------|---------|
| `task_card` | Task definition with acceptance criteria | Codex (planning) |
| `result_report` | Execution results with check status | Claude (reporting) |
| `action_request` | Request for information or decision | Both |
| `review` | Review verdict and findings | Codex (review) |

### Parsing Strategy

- **Lenient**: Require only top-level envelope and core keys
- **Tolerant**: Accept extra fields and minor formatting differences
- **Fallback**: If YAML parsing fails, fall back to unstructured parsing

### Multi-turn Exchange

The protocol supports two independent iteration modes:

#### Planning Exchange (`exchange.*`)

Iterative discussion during planning phase:

**Flow Control:**
- `next_action: continue` - Request further exchange
- `next_action: stop` - Exchange complete
- `type: action_request` - Implies `next_action: continue`

**Settings:**
- `exchange.enabled: true` - Global kill-switch
- `exchange.max_iterations: 3` - Max rounds
- `exchange.user_confirm: on_important` - User confirmation timing
- `exchange.history_mode: summarize` - History management

**Termination Conditions:**
1. `next_action: stop` received
2. `exchange.max_iterations` reached
3. Repeated same question detected

#### Review Iteration (`review.*`)

Auto-iterate on review findings:

**Flow:**
1. Codex reviews → CONDITIONAL/FAIL
2. Claude fixes issues
3. Re-request review
4. Repeat until PASS or max reached

**Settings:**
- `review.enabled: true` - Enable auto-iteration
- `review.max_iterations: 5` - Higher than exchange (goal is clear, diff is small)
- `review.user_confirm: never` - Auto-iterate without confirmation

**Note:** `exchange.*` and `review.*` are completely independent (no inheritance).

## References

Detailed documentation in `references/`:

- **`protocol-cheatsheet.yaml`** - Minimal protocol header for prompts
- **`protocol-schema.yaml`** - Full protocol schema with examples
- **`planning-prompt.md`** - Template for requesting plans
- **`review-prompt.md`** - Template for requesting reviews
- **`codex-options.md`** - Codex CLI configuration options
- **`workflow-patterns.md`** - Alternative workflow patterns
