# Codex CLI Configuration Options

Reference documentation for `codex exec` command parameters.

## codex exec Command

Execute a single prompt with Codex CLI.

### Basic Syntax

```bash
codex exec [OPTIONS] [PROMPT]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--model <MODEL>` | `-m` | Model the agent should use |
| `--sandbox <MODE>` | `-s` | Sandbox policy for shell commands |
| `--cd <DIR>` | `-C` | Working directory |
| `--config <key=value>` | `-c` | Override config values |
| `--profile <PROFILE>` | `-p` | Configuration profile from config.toml |
| `--image <FILE>` | `-i` | Attach image(s) to the prompt |
| `--full-auto` | | Automatic execution mode (sandbox workspace-write) |
| `--output-last-message <FILE>` | `-o` | Write last message to file |
| `--json` | | Print events as JSONL |

### Sandbox Modes (`-s, --sandbox`)

| Mode | Description | Use Case |
|------|-------------|----------|
| `read-only` | Cannot modify files | Safe for planning/review |
| `workspace-write` | Can write to workspace | For implementation tasks |
| `danger-full-access` | Full system access | Use with extreme caution |

**Default for collaboration**: `read-only` (Codex plans/reviews, Claude implements)

### Full Auto Mode

`--full-auto` is a convenience alias that sets:
- Sandbox: `workspace-write`
- Automatic approval for most operations

Use this when you want Codex to execute without manual approvals.

### Config Overrides (`-c, --config`)

Override settings from `~/.codex/config.toml`:

```bash
# Set model
codex exec -c model="gpt-5.6-sol" "prompt"

# Set sandbox permissions
codex exec -c 'sandbox_permissions=["disk-full-read-access"]' "prompt"

# Multiple overrides
codex exec -c model="gpt-5.6-sol" -c 'features.stream=true' "prompt"
```

## Model Selection

### Available Models

Model availability changes with OpenAI releases — do not hardcode model names in prompts or settings unless there is a specific reason.

- **Default (recommended)**: omit `model` / `-m` entirely; Codex uses the `model` value from `~/.codex/config.toml`
- Example current models: `gpt-5.6-sol`, `gpt-5.5` (check `~/.codex/config.toml` or the Codex release notes for what is currently available)
- Retired model names (e.g., `o3`, `o4-mini`, `gpt-5.x-codex`) will fail or be silently migrated

### Selection Criteria

| Task Type | Recommendation |
|-----------|----------------|
| Planning / review / architectural decisions | Codex default (usually the most capable current model) |
| Quick validation on a budget | A lighter current model, if one is available |

## Configuration Hierarchy

Settings are applied in order (later overrides earlier):

1. Codex installation defaults
2. `~/.codex/config.toml` (user global)
3. Plugin safe defaults
4. Project `.claude/codex-collab.local.md`
5. Explicit command arguments (`-c`, `-m`, `-s`, etc.)

## Example Commands

### Planning Request

```bash
codex exec \
  -s read-only \
  "Create implementation plan for adding user authentication"
```

### Review Request

```bash
codex exec \
  -s read-only \
  "Review the following changes:

## Changes Made
- Modified src/auth.ts: Added login function
- Created src/middleware/auth.ts: JWT validation

## Diff Summary
[diff content here]

Provide a code review with verdict (PASS/CONDITIONAL/FAIL)."
```

### With Specific Model

```bash
codex exec \
  -m gpt-5.6-sol \
  -s read-only \
  "Quick validation: Is this function safe? [code here]"
```

### Full Auto Execution

```bash
codex exec --full-auto "Fix the linting errors in src/"
```

### Save Output to File

```bash
codex exec \
  -s read-only \
  -o .codex-output.txt \
  "Analyze this codebase structure"
```

**Note**: Use project directory (`.codex-output.txt`) instead of `/tmp` to share between WSL sessions. These temporary files are excluded via `.gitignore` (see project root).

## Important Notes

### Stateless vs. Resumed Execution

A plain `codex exec` call starts a **new** thread with no history. To continue a conversation, resume the thread by id (`codex exec resume <uuid>`, see *Stateful Sessions* below) — codex-collab does this via `codex_run_exec_session`.

When a new thread is started (first turn, legacy state, sandbox change, or a lost thread):
- Include relevant code/context in the prompt
- For review, include both the original plan and the changes made
- Do not reference "previous" conversations the new thread has never seen

### Long Prompts

For long prompts, write to a file and use stdin pipe format (recommended to avoid escaping issues):

```bash
cat > prompt.txt << 'EOF'
Your long prompt here
with multiple lines
and code blocks
EOF

codex exec -s read-only - < prompt.txt
```

### Stdin Input

Read prompt from stdin using `-` argument:

```bash
# Redirect from file (recommended)
codex exec -s read-only - < prompt.txt

# Pipe from echo (may not work reliably with all codex versions)
echo "Your prompt" | codex exec -s read-only -
```

**Note**: The redirect format (`codex exec - < file`) is preferred over pipe format (`cat file | codex exec -`) for reliability.

## Subcommands

### codex exec resume

Resume a previous session:

```bash
codex exec resume <session-id>  # Resume specific session (used by codex-collab)
codex exec resume --last        # Resume most recent session (NOT used by codex-collab: may pick another workflow's thread)
```

### codex exec review

Run a code review against the current repository:

```bash
codex exec review
```

## codex review Command

Run a code review against the current repository's uncommitted changes.

### Basic Syntax

```bash
codex review [OPTIONS] [PROMPT]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--uncommitted` | | Review uncommitted/staged changes |
| `--config <key=value>` | `-c` | Override config values (e.g., `model="gpt-5.6-sol"`) |

### Usage

```bash
# Review uncommitted changes
codex review --uncommitted

# With custom prompt
codex review --uncommitted "Focus on security vulnerabilities"

# With model override
codex review --uncommitted -c 'model="gpt-5.6-sol"'
```

### Key Differences from `codex exec`

| Aspect | `codex review` | `codex exec` |
|--------|---------------|-------------|
| Diff collection | Automatic (uncommitted changes) | Manual (must include in prompt) |
| Purpose | Specialized for code review | General-purpose execution |
| Prompt | Optional (enhances default review) | Required |
| Sandbox | `-c sandbox_mode="..."` only | Configurable via `-s` |

> **Flags:** `codex review` does **not** accept `-s` or `-m` (`unexpected argument`, verified on 0.154.0). Use `-c 'sandbox_mode="read-only"'` and `-c 'model="..."'` instead (`codex_run_review` already does this).

### Integration with codex-collab

The recommended approach for review in codex-collab is:
1. **Primary**: Use `codex review --uncommitted` via `codex_run_review()`
2. **Fallback**: If `codex review` fails, continue the planning thread with `codex_run_exec_session()` and a diff file reference

```bash
# Primary: codex review
codex_run_review "$OUTPUT_FILE" "$MODEL" || REVIEW_EXIT=$?

# Fallback: resume the plan thread (Codex reviews against its own plan)
if [ "$REVIEW_EXIT" -ne 0 ]; then
  rc=0
  codex_run_exec_session "$PROMPT_FILE" "$OUTPUT_FILE" "read-only" "$MODEL" "$PLAN_THREAD_ID" > /dev/null || rc=$?
fi
```

## Running with Helper Functions

The recommended way to run Codex within codex-collab is via the helper functions in `scripts/codex-helpers.sh`:

```bash
export CODEX_SKILL_CONTEXT=1
source scripts/codex-helpers.sh

# For stateful execution (new thread, then resume)
PROMPT_FILE=$(codex_write_prompt "$PROMPT_CONTENT" "plan")
OUTPUT_FILE="$(codex_tmp_path 'codex-output.md')"
rc=0
THREAD_ID=$(codex_run_exec_session "$PROMPT_FILE" "$OUTPUT_FILE" "read-only" "") || rc=$?   # model "" → Codex default
rc=0
THREAD_ID=$(codex_run_exec_session "$NEXT_PROMPT_FILE" "$OUTPUT_FILE" "read-only" "" "$THREAD_ID") || rc=$?

# For one-shot stateless execution
codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" "read-only"

# For code review (preferred for review phase)
REVIEW_OUTPUT="$(codex_tmp_path 'codex-review-output.md')"
codex_run_review "$REVIEW_OUTPUT"
```

### Helper Functions

| Function | Purpose |
|----------|---------|
| `codex_write_prompt(content, prefix)` | Write prompt to temp file, return path |
| `codex_run_exec(prompt, output, sandbox, model)` | Run codex exec (stateless) with full I/O handling |
| `codex_run_exec_session(prompt, output, sandbox, model, [thread_id])` | Run `codex exec --json` / `codex exec resume`; prints the thread id; return codes 0/2/3/4/5 |
| `codex_extract_thread_id(jsonl)` | Extract the thread id from a `thread.started` event |
| `codex_is_valid_uuid(id)` / `codex_is_valid_sandbox(mode)` | Validators |
| `codex_run_review(output, model, sandbox)` | Run codex review --uncommitted with fallback support (sandbox defaults to read-only) |
| `codex_infer_verdict(response)` | Infer verdict from review response (metadata → [P1]-[P4] → pass) |
| `codex_extract_review_findings(response)` | Extract findings from review response |
| `codex_build_exec_command(prompt, sandbox, model)` | Build command string (for eval) |
| `codex_strip_ansi(text)` | Remove ANSI escape codes from output |
| `codex_save_session_state(task_id, mode, thread_id, sandbox, workflow)` | Save session state to JSON (task_id-scoped) |
| `codex_load_session_state(task_id)` | Load session state, sets SESSION_* globals; migrates legacy mcp/bash files (0 / 1 not found / 2 I/O failure) |
| `codex_save_thread(task_id, name, value)` | Save a raw named-thread value |
| `codex_save_thread_session(task_id, name, uuid, sandbox)` | Save named thread as `uuid\|sandbox` (for claude-leads Thread B/C) |
| `codex_load_session_thread(task_id, sandbox)` | Main thread UUID only if resumable with that sandbox (0 / 1 none, legacy, invalid or sandbox mismatch / 2 I/O failure) |
| `codex_load_thread(task_id, name)` / `codex_load_thread_sandbox(task_id, name)` | Load named thread UUID / sandbox (0 / 1 none or invalid / 2 I/O failure) |
| `codex_diff_tier(diff_content)` | Determine diff size tier (small/medium/large) |
| `codex_sanitize_task_id(raw_id)` | Sanitize task_id for filename safety |
| `codex_json_escape(value)` | Escape string for JSON embedding |

### Key Points

- **Blocking execution**: Both `codex exec` and `codex review` block until completion, no polling needed
- **ANSI stripping**: Output may contain ANSI escape codes; `codex_run_exec` and `codex_run_review` handle this automatically. `codex_run_exec_session` reads the body from `-o`, which has no ANSI codes
- **Stdin input**: Use `codex exec - < file` format to avoid escaping issues
- **Timeout**: Bash tool has max 600s (10 minutes) timeout; set `codex.wait_timeout` accordingly
- **Fallback**: `codex_run_review()` returns non-zero on any failure; caller should fall back to `codex_run_exec_session()` on the plan thread

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| command not found | Codex CLI not installed | Install Codex CLI or add to PATH |
| Timeout | Complex operation | Simplify prompt or increase `codex.wait_timeout` |
| Model unavailable | API issues | Try different model or retry |
| API error | Rate limit or auth issue | Check API key and quota |

### Timeout Considerations

For long operations, consider:
- Breaking task into smaller prompts
- Using simpler model for initial pass
- Providing more specific context to reduce thinking time

## Stateful Sessions: `codex exec --json` + `codex exec resume`

codex-collab keeps multi-turn context by resuming Codex threads from the CLI.

```bash
# New thread: stdout = JSONL events, -o = final agent message
codex exec -s read-only [-m MODEL] --json -o out.md - < prompt.txt > events.jsonl 2> stderr.log

# Continue: -s goes BETWEEN exec and resume (resume itself has no -s)
codex exec -s read-only [-m MODEL] resume <THREAD_UUID> --json -o out.md - < next.txt > events.jsonl 2> stderr.log
```

Event lines (one JSON object per line, `type` is the first key):

```
{"type":"thread.started","thread_id":"<uuid>"}
{"type":"turn.started"}
{"type":"item.started",...} / {"type":"item.completed","item":{"type":"agent_message",...}}
{"type":"turn.completed","usage":{...}}
```

Rules used by `codex_run_exec_session`:
- Never use `resume --last` (may pick another workflow's thread) or `--ephemeral` (not resumable).
- Pass a **UUID** only: a non-UUID argument is treated as a thread *name*; an unknown name silently starts a **new** thread with a different id (exit 0).
- The resumed turn must report the same `thread_id`; a mismatch is rc 5.
- One thread = one sandbox (the CLI would honor a different `-s`, but mixing sandboxes in one conversation is not allowed by codex-collab).

### Verified behavior (codex-cli 0.154.0, 2026-09-15)

| Case | Result |
|------|--------|
| Resume keeps context | Codeword given in turn 1 recalled in turn 2; same `thread_id` |
| `-s read-only` resume of a workspace-write thread | Write denied (`Read-only file system`), no file created → CLI `-s` is honored |
| `-s workspace-write` resume of a read-only thread | File created → CLI `-s` is honored (`-c sandbox_mode` not needed) |
| Non-existent UUID | exit 1, JSONL empty, `-o` not created, stderr `thread/resume failed: no rollout found for thread id <id> (code -32600)` → rc 3 |
| Thread removed with `codex delete --force` | Same as non-existent UUID → rc 3 |
| Archived thread (`codex archive`) | exit 1, JSONL empty, stderr `session <id> is archived. Run codex unarchive …` → rc 4 (not auto-retried) |
| Non-UUID thread name | exit 0, **new** thread started → rejected up front (rc 2) |
| `--json` + `-o` | `-o` contains the final message; every JSONL line matches `^\{"type":"…"` |

### Return codes of `codex_run_exec_session`

| rc | Meaning | Caller action |
|----|---------|---------------|
| 0 | Completed; thread id printed | Read `-o` output, persist thread id |
| 2 | Precondition / local I/O error; codex not started | Report and stop |
| 3 | Resume rejected before any turn (thread not found) | Rebuild context from the role's inputs in a new thread, **once** |
| 4 | Outcome unknown (non-zero exit, malformed/missing JSONL, no `turn.completed`) | No automatic retry; inspect `*.stderr.log` (+ `git status` for workspace-write); ask user |
| 5 | Completed but invalid (empty output, missing/ambiguous/mismatched thread id) | Same as 4 |

## `codex mcp-server` removal

`codex mcp-server` (the `codex` / `codex-reply` MCP tools) was deprecated in rust-v0.149.0 (openai/codex#39657) and removed in rust-v0.154.0 (openai/codex#42993). The official successor for rich integrations is the experimental `codex app-server` (JSON-RPC, not MCP-compatible). codex-collab uses `codex exec` / `codex exec resume` instead; remove any `codex mcp-server` entry from your MCP configuration (e.g. `~/.mcp.json`).
