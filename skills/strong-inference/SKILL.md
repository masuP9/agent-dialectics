---
name: strong-inference
description: 'This skill should be used when the user wants to "investigate a bug", "debug an issue", "figure out why something is happening", "find the root cause", "troubleshoot", "強い推論で調査", "仮説を立てて検証", "原因を特定", "バグの原因調査", "なぜ動かないか調べて", "問題を切り分け", "原因不明", "デバッグ", or mentions systematic hypothesis-driven debugging. NOTE: Use this for investigating UNKNOWN causes, not for validating design proposals (use devils-advocate for that).'
argument-hint: '[problem description] [--mode codex|claude-only]'
---

# Strong Inference Skill

Apply the "Strong Inference" methodology to investigate problems systematically through competing hypotheses and decisive experiments.

## Overview

Strong Inference is a scientific method that accelerates problem-solving by:
1. Generating multiple **competing** hypotheses
2. Designing experiments that **eliminate** hypotheses
3. Iterating until the most likely explanation remains

This skill helps developers investigate bugs, performance issues, and unexpected behaviors using a structured, hypothesis-driven approach.

**Key Feature**: In codex mode, Codex generates the competing hypotheses and reviews the conclusion, while Claude gathers context, designs and executes verifications.

## 利用量ポリシーとロール表

1. **Codex 役は常に fresh**。反復（ラウンド、再レビュー）は「前回までの要約（確定事項・未解決・却下案）+ 必要な抜粋」を含む自己完結プロンプトで再投入する。thread を継続しない
2. **事実はプロンプトに持たせる**。Claude 側で読んだファイル抜粋・行番号・確認済み事実を prompt.md に入れる。「リポジトリを探索して検証せよ」とは指示しない。ディスク読取を許すのは、下表で「読取が役割」と宣言したロールだけ
3. **Web 検索は使わない**よう、全ロールの prompt に明記する
4. **入力トークン上限**: 1 呼び出しあたり 10 万トークン。超えたらプロンプトを見直す（例外は下表で個別上限を宣言したロールのみ）

| ロール | 担当 | `--model` / `--effort` | ディスク読取 | 入力上限 |
|---|---|---|---|---|
| `hypothesis`（反復: `hypothesis-r<round>`） | Codex | 既定（config.toml） | 不可 | 10 万 |
| `review` | Codex | 既定（config.toml） | 不可 | 10 万 |

- `hypothesis` — Step 3. Generates 2-4 competing hypotheses. Round 1 is fed `Problem` + `Context`; round 2+ (all hypotheses eliminated) is additionally fed `Hypotheses` + `Verification Log` so the new hypotheses are built on the evidence.
- `review` — Step 7. Validates the conclusion, assesses confidence, proposes fix and prevention. Fed `Problem` + `Context` + `Hypotheses` + `Verification Log`.

Context gathering, verification design and verification execution are Claude-only in every mode.

ユーザーは実行時にこの表の model / effort を上書きできる（例: 「hypothesis は既定モデルで」）。

## Problem

$ARGUMENTS

## Prerequisites

- The user has a problem, bug, or unexpected behavior to investigate
- Relevant code context is available
- For codex mode: the codex-plugin-cc companion (`codex@openai-codex`) installed and Codex CLI logged in (checked by `run-codex-role.sh`)

## Role Distribution

| Mode | Hypothesis Gen | Verification Design | Execution | Review |
|------|----------------|---------------------|-----------|--------|
| `codex` | Codex (`hypothesis`) | Claude | Claude | Codex (`review`) |
| `claude-only` | Claude | Claude | Claude | Claude |

## Codex 役の呼び出し

<!-- shared:codex-role-protocol start (4手法で同一。変更時は 4 ファイルすべてに反映する。scripts/lint-plugin.sh の Check 7 が一致を検査) -->

Codex が担当するロールは、プラグイン同梱の `scripts/run-codex-role.sh`（公式 codex-plugin-cc companion の `task --fresh --json` を read-only で 1 回呼ぶラッパー）だけで呼ぶ。`/codex:rescue` や `codex exec` を直接使わない。

**スクリプトの場所**: このスキルの読み込み時に表示される base directory（`.../skills/strong-inference`）から `<base>/../../scripts/run-codex-role.sh` を組み立てる。`${CLAUDE_PLUGIN_ROOT}` が展開されていればそちらを優先する。

**作業ディレクトリ（対象リポジトリの外）**:

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
echo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG/strong-inference/<task-id>"
```

- `<state-dir>/state.md` — 手法の状態ファイル（相・終端状態・中断再開用）。frontmatter の `created` は `date -u +%Y-%m-%dT%H:%M:%SZ` の出力をそのまま書く（ローカル時刻に `Z` を付けない）
- `<state-dir>/<role>-<attempt>/` — Codex 呼び出し 1 回分（`attempt` は 1 から）。反復ロールは `<role>-r<round>-<attempt>`
  - `prompt.md` — 送るプロンプト。**1 行目は必ず** `<!-- agent-dialectics-role: strong-inference/<role> -->`（反復ロールは `<role>-r<round>`）
  - `inputs.json` — prompt.md と同時に Write で書く: `{"method": "strong-inference", "role": "<role>", "state_sections": ["<state.md の節名>", ...], "artifacts": ["<絶対パス>", ...]}`（prompt 組み立てに使った状態ファイル節と成果物の一覧。非漏洩検査に使う）
  - スクリプトが書く: `status.json`, `answer.md`, `meta.json`, `DONE`（成功時）/ `error.log`（失敗時）
- 対象リポジトリに `tmp/` などを作らない

**実行**（prompt.md / inputs.json を Write で書いた後。長時間になりうるので Bash の `run_in_background: true` で起動し、完了通知を待つ）:

```bash
"<plugin-root>/scripts/run-codex-role.sh" --prompt-file "<attempt-dir>/prompt.md" --cwd "<ROOT>" --out-dir "<attempt-dir>" [--model <m> --effort <e>]
```

完了通知を受けたら **終了コード → answer.md** の順に読む。

**判定の前に完了を確かめる**: 終了コードを受け取らないまま出力を見た場合は、`status.json` の `state` で判断する。`running` の間は**未完了**として扱い、待つ（`answer.md` がないことを結果不正＝終了コード 5 と判定しない）。`succeeded`（`DONE` あり）なら `answer.md` を読み、`failed` なら `exit_code` と `error.log` を根拠にする。

| 終了コード | 意味 | 対応 |
|---|---|---|
| 0 | 成功 | `answer.md` を読む。`meta.json` の `threadId`（生の UUID）を状態ファイルに `codex:<uuid>` として記録 |
| 1 | 引数エラー / attempt ディレクトリ再利用 | 呼び出し側の誤り。直して新しい attempt で |
| 2 | Codex 不可（companion 未導入・Codex CLI 未導入・未認証） | 下記「実行モード」の縮退規則 |
| 4 | 実行失敗（利用上限・turn 失敗など） | **自動再実行しない**。`error.log` を示してユーザーに判断を仰ぐ |
| 5 | 結果不正（空回答・status≠0・ファイル変更あり） | **自動再実行しない**。状態を次相へ進めずユーザーに判断を仰ぐ |

**再開規則**（中断後に attempt ディレクトリを見つけたとき）:
- `DONE` あり → 成功として `answer.md` を再利用（再投入しない）
- `status.json` が `running` かつ `pid` が生存（`kill -0 <pid>`）→ 完了を待つ（再投入しない）
- `running` だが pid が消滅し `DONE` なし → `unknown`。ユーザーに再投入してよいか確認
- `failed` → 終了コード 4/5 の規則どおりユーザー判断
- 新しい attempt（attempt+1）を作るのはユーザーが承認した場合のみ

**注意**: 手法の実行中・直後に同じリポジトリで `/codex:rescue --resume` を使わない（companion が手法のロール thread を拾って継続してしまう）。使うなら `--fresh`。
<!-- shared:codex-role-protocol end -->

## 実行モード

- `codex`（既定）: Codex 役を `run-codex-role.sh` で呼ぶ
- `claude-only`: `--mode claude-only` の明示指定時、または `run-codex-role.sh` が **終了コード 2** を返したときに、**ユーザーに明示的に警告したうえで**縮退する
- **縮退時の警告は、縮退した時点で出す（必須）**: 終了コード 2 を受け取ったら、**次のツール呼び出し（Claude サブエージェントの起動、状態ファイルの更新を含む）より前に**、ユーザー向けのテキストとして次の警告を出す。最終レポートの注記や「Claude のサブエージェントに書かせています」のような途中経過の説明では代わりにならない。理由は完了通知など取得済みの情報から書き、未取得なら「詳細未確認」とする（理由を調べるためのツール呼び出しは警告のあとで行い、必要なら補足する）

  > ⚠️ Codex を使えないため（`run-codex-role.sh` 終了コード 2: `<error.log の理由を 1 行>`）、`<role>` 以降を Claude だけで続けます（`degraded: true`）。別モデルによる独立した確認がないため、結論の確かさは下がります。
- 状態ファイルに `degraded: true|false` と `codex_call_failures`（`- {role, exit, attempt}` のリスト）を分けて記録する
- 終了コード 4 / 5 は縮退理由にしない（自動再実行も自動縮退もしない。ユーザー判断）
- 同一モデル（Claude が Claude の結論を確認）の一致を独立した裏付けに数えない
- strong-inference 固有: claude-only（縮退含む）では仮説生成・検証・結論レビューがすべて同一モデルになる。Step 7 の完了報告の Confidence に「独立レビューなし（claude-only）」と明記し、Claude 自身のレビュー結果を理由に Confidence を引き上げない

## Hypothesis Tree File (state.md)

Investigation state is persisted to `<state-dir>/state.md` (see 「Codex 役の呼び出し」 for the path; never inside the target repository):

```markdown
---
schema: strong-inference/v2
task_id: 20260202-120000-12345
created: 2026-02-02T12:00:00Z
problem: "API returns 500 intermittently"
mode: codex
degraded: false
codex_call_failures: []
iteration: 0
max_iterations: 10
hypothesis_round: 1
hypothesis_thread_id: codex:<uuid>
review_thread_id: ""
---

# Investigation: API returns 500 intermittently

## Hypotheses

### H1: Database connection pool exhausted
- Status: [X] Eliminated
- Evidence: Connection count stable at 5/20 during error window
- Verified: 2026-02-02T12:15:00Z

### H2: Race condition in cache update
- Status: [?] Pending
- Test: Add mutex logging to CacheManager.update()
- Priority: High (matches timing pattern)

### H3: External service timeout
- Status: [!] Supported
- Evidence: Errors correlate with ExternalAPI latency spikes
- Next: Verify timeout handling in ApiClient.fetch()

## Verification Log

| Time | Action | Result |
|------|--------|--------|
| 12:05 | Read db/pool.go | Found pool size config |
| 12:10 | Check connection metrics | Stable at 5/20 |
| 12:15 | Eliminated H1 | Evidence contradicts |

## Context

### Error Details
[Error messages, stack traces]

### Related Files
- db/pool.go: Description (with the excerpts / line numbers Claude read)

### Recent Changes
[Git log or change summary if relevant]
```

- v2 changes from v1: state moved to `<state-dir>/state.md`; added `degraded`, `codex_call_failures`, `hypothesis_round`, `hypothesis_thread_id`, `review_thread_id`.
- `*_thread_id` values are `codex:<uuid>` (from `meta.json`) or `claude-subagent-<role>` / empty in claude-only. They are **records only** and are never used to continue a thread.
- State section names used in `inputs.json` `state_sections`: `Problem` (frontmatter `problem`), `Context`, `Hypotheses`, `Verification Log`.

## Workflow Phases

### Phase 1: Problem Definition

When the user presents a problem:

1. **Collect information**:
   - Error messages, logs, stack traces
   - Steps to reproduce
   - Expected vs actual behavior
   - Recent changes that might be related

2. **Clarify scope**:
   - Which components are involved?
   - When did it start happening?
   - Is it reproducible consistently?

### Phase 2: Hypothesis Generation

Generate 2-4 **competing hypotheses** that are:
- **Mutually exclusive**: If H1 is true, H2 cannot be true
- **Testable**: Can be verified or eliminated with evidence
- **Specific**: Clear enough to design a decisive test

**Example hypotheses for "API returns 500 intermittently":**
```
H1: Database connection pool exhausted under load
H2: Race condition in cache update causing stale data
H3: External service timeout not handled properly
H4: Memory leak causing OOM conditions
```

### Phase 3: Verification Design

For each hypothesis, design a "killer experiment" that:
- Can **eliminate** the hypothesis if the result is negative
- Requires **minimal effort** for maximum information gain
- Is **safe** to execute (no production impact)

**Prioritize experiments by:**
1. Ease of execution (quick wins first)
2. Discriminating power (eliminates multiple hypotheses)
3. Risk level (non-destructive first)

### Phase 4: Verification Execution

Execute verifications in priority order:
- Code inspection (reading files, checking logic)
- Log analysis (searching for patterns)
- Test execution (running specific tests)
- Instrumentation (adding debug output)

**Safety guards:**
- Confirm before any file modifications
- Set timeouts for long-running operations
- Log all executed commands

### Phase 5: Analysis and Iteration

After each verification:

1. **Record evidence**: What was observed?
2. **Update hypothesis status**:
   - `[X]` Eliminated (evidence contradicts)
   - `[?]` Pending (not yet tested)
   - `[!]` Supported (evidence aligns)
3. **Refine remaining hypotheses** based on new information
4. **Generate new hypotheses** if all were eliminated

### Phase 6: Conclusion

When one hypothesis has strong supporting evidence:

1. **Summarize findings**: Evidence trail and reasoning
2. **Propose solution**: Based on confirmed hypothesis
3. **Suggest prevention**: How to avoid similar issues

## Workflow Instructions

### Step 1: Parse Arguments and Initialize

**1. Parse mode from the Problem text above:**

- If it contains `--mode codex` or `--mode claude-only`, take that as the mode override and remove the flag from the problem description.
- Otherwise the mode is `codex` (default). Codex availability is not probed up front; it is determined by the first `run-codex-role.sh` call (exit code 2 → degrade per 「実行モード」).
- If `--mode claude-only` was given, tell the user the investigation runs without independent Codex review.

**2. Resolve the state directory and task ID:**

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
TASK_ID="$(date +%Y%m%d-%H%M%S)-$RANDOM"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG/strong-inference/$TASK_ID"
mkdir -p "$STATE_DIR"
echo "ROOT=$ROOT"
echo "TASK_ID=$TASK_ID"
echo "STATE_DIR=$STATE_DIR"
```

Remember `ROOT`, `TASK_ID` and `STATE_DIR` for later steps (shell state does not persist between Bash calls; use the printed absolute paths).

**3. Create `<STATE_DIR>/state.md` with the Write tool:**

```markdown
---
schema: strong-inference/v2
task_id: <TASK_ID>
created: <ISO-8601 timestamp>
problem: "<problem description, double quotes escaped>"
mode: <codex|claude-only>
degraded: false
codex_call_failures: []
iteration: 0
max_iterations: 10
hypothesis_round: 1
hypothesis_thread_id: ""
review_thread_id: ""
---

# Investigation: <problem description>

## Hypotheses

(Pending generation)

## Verification Log

| Time | Action | Result |
|------|--------|--------|
```

### Step 2: Gather Context

**Create task:**
- subject: "Gather problem context"
- description: "Collect error logs, related code, and reproduction steps"
- activeForm: "Gathering context"

**Collect information:**
1. Ask user for any error messages, logs, or stack traces
2. Identify potentially affected files
3. Read relevant code sections
4. Check recent git changes if applicable

**Update state.md with a context section using the Edit tool** (append after the `## Verification Log` table). Because Codex roles cannot read the disk, include the actual excerpts (with file paths and line numbers) that matter, not just file names:

```markdown
## Context

### Error Details
[Error messages, stack traces]

### Related Files
- file1.go:40-58: Description + relevant excerpt
- file2.go: Description

### Recent Changes
[Git log or change summary if relevant]
```

### Step 3: Generate Hypotheses

**Task transition:**
- Mark previous task completed
- Create: "Generate competing hypotheses"
- activeForm: "Generating hypotheses"

`<round>` is `hypothesis_round` from state.md (1 for the first generation; incremented each time Step 6 returns here because all hypotheses were eliminated).

**If mode = codex:**

1. Write `<STATE_DIR>/hypothesis-r<round>-<attempt>/prompt.md` with the Write tool, following `references/hypothesis-template.md`. The prompt is self-contained:

   - Line 1: `<!-- agent-dialectics-role: strong-inference/hypothesis-r<round> -->`
   - A directive to answer in the language of the user's conversation (e.g. 「日本語で回答してください。」)
   - A directive: do not use web search, do not explore the repository; rely only on the facts in this prompt
   - `## Problem` — frontmatter `problem`
   - `## Context` — the full `## Context` section of state.md
   - **Round 2+ only**: `## Eliminated Hypotheses` — the full `## Hypotheses` section of state.md, and `## Verification Log` — the full log table, with the instruction that new hypotheses must be consistent with this evidence and must not restate eliminated ones
   - `## Task` / `## Response Format` from the template (2-4 mutually exclusive, testable, specific, prioritized hypotheses; statement, reasoning, elimination test, verification approach for each)

2. Write `inputs.json` in the same directory:
   - Round 1: `{"method": "strong-inference", "role": "hypothesis-r1", "state_sections": ["Problem", "Context"], "artifacts": []}`
   - Round 2+: `{"method": "strong-inference", "role": "hypothesis-r<round>", "state_sections": ["Problem", "Context", "Hypotheses", "Verification Log"], "artifacts": []}`

3. Run (Bash with `run_in_background: true`, then wait for the completion notification):

```bash
"<plugin-root>/scripts/run-codex-role.sh" --prompt-file "<STATE_DIR>/hypothesis-r<round>-<attempt>/prompt.md" --cwd "<ROOT>" --out-dir "<STATE_DIR>/hypothesis-r<round>-<attempt>"
```

4. Handle the exit code per 「Codex 役の呼び出し」. On `0`, read `answer.md`, record `hypothesis_thread_id: codex:<meta.json threadId>`, and use the Edit tool to replace `(Pending generation)` (round 1) or the previous hypotheses block (round 2+, keep the eliminated ones under a `### Previously eliminated (round <n>)` sub-heading) with the new hypotheses. On `2`, record the failure in `codex_call_failures`, set `degraded: true` and `mode: claude-only`, warn the user, and continue with the claude-only path. On `4`/`5`, record the failure and stop for the user's decision.

**If mode = claude-only:**

Generate hypotheses directly using reasoning:
1. Analyze the problem and context (round 2+: and the eliminated hypotheses and verification log)
2. Generate 2-4 competing hypotheses
3. Rank by likelihood
4. Update state.md using the Edit tool

### Step 4: Design Verification Tests

**Task transition:**
- Create: "Design verification experiments"
- activeForm: "Designing experiments"

For each hypothesis, design a "killer experiment":

1. **Prioritize by:**
   - Ease of execution (quick wins first)
   - Discriminating power (can eliminate multiple hypotheses)
   - Safety (non-destructive tests first)

2. **For each experiment, define:**
   - What to check/run
   - Expected result if hypothesis is true
   - Expected result if hypothesis is false
   - Commands or code inspection needed

3. **Update state.md using the Edit tool:**

```markdown
### H1: [Hypothesis]
- Status: [?] Pending
- Test: [Specific verification to perform]
- If true: [Expected observation]
- If false: [Expected observation]
- Priority: High/Medium/Low
```

### Step 5: Execute Verifications

**Task transition:**
- Create: "Execute verification experiments"
- activeForm: "Verifying hypotheses"

Execute tests in priority order:

**For each verification:**

1. **Announce action:**
```
Verifying H1: [Hypothesis name]
Test: [What we're checking]
```

2. **Execute verification** (code reading, log analysis, test running):
   - Use Read tool for code inspection
   - Use Grep for log/pattern search
   - Use Bash for running tests (with user confirmation)

3. **Record result in state.md**: use the Edit tool to append a row to the `## Verification Log` table:

```markdown
| HH:MM | Checked [specific thing] | Found [specific result] |
```

4. **Update hypothesis status** using the Edit tool:
   - `[X]` Eliminated - evidence contradicts
   - `[!]` Supported - evidence aligns
   - `[?]` Pending - not yet conclusive

5. **Safety check before destructive operations:**

Use AskUserQuestion tool before running tests or modifying files:
- "This verification requires running tests. Proceed?"
- "This will add debug logging to file.go. Approve?"

### Step 6: Analyze and Iterate

After each verification round:

1. **Display current status:**
```
Strong Inference Investigation
==============================
Problem: [Problem description]

Hypotheses:
  [X] H1: [Hypothesis] - Eliminated (evidence: ...)
  [!] H2: [Hypothesis] - Supported (evidence: ...)
  [?] H3: [Hypothesis] - Pending

Iteration: 2/10
```

2. **Increment `iteration`** in the state.md frontmatter with the Edit tool. If the new value reaches `max_iterations`, report the investigation as inconclusive and ask the user whether to continue.

3. **Check termination conditions:**
   - One hypothesis strongly supported → Go to Step 7
   - All hypotheses eliminated → increment `hypothesis_round` and generate new hypotheses (return to Step 3; the round 2+ prompt carries the eliminated hypotheses and the log)
   - max_iterations reached → Report inconclusive and ask user

4. **If continuing:**
   - Refine remaining hypotheses based on new evidence
   - Design next verification
   - Return to Step 5

### Step 7: Conclude Investigation

**Task transition:**
- Create: "Summarize findings and propose solution"
- activeForm: "Concluding investigation"

**If mode = codex:**

Request a Codex review of the findings as a fresh, self-contained call (no hypothesis-thread continuation; the prompt embeds the whole investigation state).

1. Write `<STATE_DIR>/review-<attempt>/prompt.md`:

````markdown
<!-- agent-dialectics-role: strong-inference/review -->
[Directive to answer in the language of the user's conversation]
Do not use web search and do not explore the repository. Base the review only on the investigation state below.

Review the Strong Inference investigation results.

## Problem
<frontmatter problem>

## Context
<full ## Context section of state.md>

## Hypotheses
<full ## Hypotheses section of state.md>

## Verification Log
<full ## Verification Log table of state.md>

## Task

1. Validate the conclusion based on evidence
2. Assess confidence level (High/Medium/Low)
3. Suggest specific fix for the root cause
4. Recommend prevention measures

## Response Format

```markdown
## Review

### Confidence Assessment
[High/Medium/Low] - [Reasoning]

### Recommended Fix
[Specific code changes or actions]

### Prevention
[How to avoid similar issues]
```

---
status: stop
verdict: pass
---
````

2. Write `inputs.json`: `{"method": "strong-inference", "role": "review", "state_sections": ["Problem", "Context", "Hypotheses", "Verification Log"], "artifacts": []}`

3. Run (Bash with `run_in_background: true`):

```bash
"<plugin-root>/scripts/run-codex-role.sh" --prompt-file "<STATE_DIR>/review-<attempt>/prompt.md" --cwd "<ROOT>" --out-dir "<STATE_DIR>/review-<attempt>"
```

4. Handle the exit code per 「Codex 役の呼び出し」. On `0`, read `answer.md` and record `review_thread_id: codex:<uuid>`. On `2`, degrade (record the failure, `degraded: true`, warn the user) and review in claude-only mode. On `4`/`5`, do not retry automatically; show `error.log` and ask the user (retry with a new attempt / conclude without Codex review / stop).

**If mode = claude-only:** review the conclusion yourself, and mark the Confidence as 「独立レビューなし（claude-only）」.

**Report to user:**

```markdown
## Investigation Complete

**Problem:** [Original problem]

**Root Cause:** [Confirmed hypothesis]
**Confidence:** High/Medium/Low

### Evidence Trail
1. [First evidence point]
2. [Second evidence point]
3. [Third evidence point]

### Recommended Fix
[Specific solution based on root cause]

### Prevention
[Suggestions to avoid similar issues]

### Investigation Log
See: <STATE_DIR>/state.md
```

### Step 8: Cleanup (Optional)

State directories are kept outside the target repository so that interrupted investigations can be resumed. Do **not** delete them automatically. If the user asks for cleanup, list the candidates first and delete only the directories the user confirms:

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
BASE="${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG/strong-inference"
find "$BASE" -mindepth 1 -maxdepth 1 -type d -mtime +7 2>/dev/null
```

## Safety Guards

Before executing verification commands:
- **Confirm destructive operations**: File changes, test execution
- **Set timeout**: Default 60 seconds per operation
- **Log all commands**: Record in verification log

**Stop conditions:**
- All hypotheses eliminated (request new hypotheses)
- `max_iterations` reached (default: 10)
- User requests stop

## Error Handling

**If Codex is unavailable in codex mode (`run-codex-role.sh` exit 2):**
- Degrade to claude-only per 「実行モード」 and record `degraded: true`
- Inform user: "Codex not available, proceeding with Claude-only mode (no independent review)"

**If a Codex call fails (exit 4/5):**
- Do not retry or degrade automatically; show `error.log` and ask the user

**If verification times out:**
- Record timeout in log
- Ask user whether to retry or skip

**If all hypotheses eliminated:**
- Summarize what was learned
- Ask user for additional context
- Generate new hypotheses based on evidence (Step 3, next round)

## Output Format

### Progress Display

```
Strong Inference Investigation
==============================
Problem: API returns 500 error intermittently

Hypotheses:
  [X] H1: Database connection pool exhausted
      Evidence: Connection count normal (eliminated)

  [!] H2: Race condition in cache update
      Evidence: Timing matches error pattern (supported)

  [?] H3: External service timeout
      Evidence: Pending verification

Current: Designing test for H2
```

### Completion Report

```
Investigation Complete
======================
Problem: API returns 500 error intermittently

Root Cause: Race condition in CacheManager.update()
Confidence: High (3 supporting evidence points)

Evidence Trail:
1. Errors occur only during cache refresh window
2. Adding mutex eliminated the error
3. Race condition visible in thread dump

Recommended Fix:
- Add mutex lock in CacheManager.update() line 45
- Consider using sync.RWMutex for better concurrency

Prevention:
- Add race detector to CI pipeline
- Review other cache operations for similar patterns
```

## Compact Recovery

If compacted during investigation:

1. Run `TaskList` to see progress
2. Find the state file: the newest `<state-base>/strong-inference/*/state.md` (state-base = `${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/<SLUG>`, computed as in Step 1). If several exist, ask the user which investigation to resume
3. For any `hypothesis-r<round>-<attempt>/` or `review-<attempt>/` directory without a recorded result, apply the attempt-directory 再開規則 in 「Codex 役の呼び出し」 (never re-submit automatically)
4. Resume from current phase based on state

**State to Phase mapping:**
| State | Resume at |
|-------|-----------|
| "Pending generation" in Hypotheses | Step 3 |
| Hypotheses listed, all [?] | Step 4 or 5 |
| Mix of [X], [!], [?] | Step 5 or 6 |
| All [X] | Step 3 (next `hypothesis_round`) |
| One [!] with strong evidence | Step 7 |

## Invoking the Skill

```bash
# Basic usage - investigate a problem
/agent-dialectics:strong-inference API sometimes returns 500 errors

# With mode selection
/agent-dialectics:strong-inference --mode claude-only Why is the test flaky?

# Japanese
/agent-dialectics:strong-inference このバグの原因を調査して
```

## Notes

- Hypothesis tree is persisted (outside the target repository) to survive compaction
- Each investigation gets a unique task ID and state directory
- Verification log provides audit trail
- Default max_iterations is 10 to prevent runaway investigations
- Always confirm before destructive operations
- Every Codex call is fresh; repeated hypothesis rounds carry prior evidence through the prompt, not a thread

## References

Detailed templates in `references/`:

- **`hypothesis-template.md`** - Prompt template for the Codex `hypothesis` role
- **`verification-patterns.md`** - Common verification strategies
