---
name: devils-advocate
description: 'This skill should be used when the user wants to "stress-test a design", "challenge an idea", "red team a proposal", "get critical feedback on a design", "validate a design", "adversarial architecture review", "risk assessment", "設計を検証して", "反論をもらいたい", "設計を批判的にレビュー", "デビルズアドボケート", "ストレステスト", "弱点を指摘して", "穴を見つけて", "この設計で良いか", "リスク評価", "設計のアーキテクチャレビュー", or mentions structured adversarial review of a proposal or design. NOTE: Use this for validating PROPOSALS and DESIGNS through adversarial debate, NOT for generic code review, PR review, or normal review requests (use /codex:review or /codex:adversarial-review for those). Also NOT for investigating unknown bugs (use /codex-collab:strong-inference for that).'
argument-hint: '[proposal] [--mode codex|claude-only] [--max-rounds N]'
---

# Devil's Advocate

Apply the Devil's Advocate methodology to stress-test hypotheses, designs, and proposals through structured adversarial debate.

## Proposal

$ARGUMENTS

## Overview

Devil's Advocate is a critical thinking technique that improves decision quality by:
1. Systematically challenging assumptions and proposals
2. Identifying weaknesses before implementation
3. Refining ideas through structured debate
4. Reaching more robust conclusions

This skill helps developers validate designs, proposals, and decisions using a structured Blue Team (propose/defend) vs Red Team (critique/challenge) approach.

**Key Feature**: In codex mode, Codex serves as the Red Team critic while Claude serves as the Blue Team advocate.

## 利用量ポリシーとロール表

1. **Codex 役は常に fresh**。反復（ラウンド、再レビュー）は「前回までの要約（確定事項・未解決・却下案）+ 必要な抜粋」を含む自己完結プロンプトで再投入する。thread を継続しない
2. **事実はプロンプトに持たせる**。Claude 側で読んだファイル抜粋・行番号・確認済み事実を prompt.md に入れる。「リポジトリを探索して検証せよ」とは指示しない。ディスク読取を許すのは、下表で「読取が役割」と宣言したロールだけ
3. **Web 検索は使わない**よう、全ロールの prompt に明記する
4. **入力トークン上限**: 1 呼び出しあたり 10 万トークン。超えたらプロンプトを見直す（例外は下表で個別上限を宣言したロールのみ）

| ロール | 担当 | `--model` / `--effort` | ディスク読取 | 入力上限 |
|---|---|---|---|---|
| `blue`（Blue Team: 提示・防御） | Claude（メインセッション） | — | 可（Context 収集） | — |
| `red-r<N>`（Red Team: ラウンド N の批評、最終ラウンドは判定も） | Codex | 既定（config.toml） | 不可 | 10 万 |

ユーザーは実行時にこの表の model / effort を上書きできる（例: 「red は既定モデルで」）。

`red-r<N>` が prompt.md に入れる state.md の節（inputs.json の `state_sections` にも同じ名前を列挙する）:

| ラウンド | `state_sections` |
|---|---|
| 1 | `Context`, `Debate Log/Round 1/Blue Team` |
| 2 以降 | `Context`, `Snapshot`, `Debate Log/Round <N-1>/Red Team`, `Debate Log/Round <N>/Blue Team` |

- ラウンド N-2 以前の Debate Log は貼らない（`Snapshot` が要約として持ち越す）。Context 抜粋に使った成果物ファイルは `artifacts` に絶対パスで列挙する
- Blue Team の防御は Red Team の判定を代行しない。指摘の解決状態を確定させるのは次ラウンドの Red Team の回答だけ

## Comparison with Strong Inference

| Aspect | Strong Inference | Devil's Advocate |
|--------|------------------|------------------|
| Purpose | Verify hypothesis through experiments | Stress-test proposal through debate |
| Method | Competing hypotheses + decisive experiments | Adversarial critique + iterative refinement |
| Output | Root cause with evidence trail | Refined proposal with verdict |
| Best For | Debugging, investigation, unknown causes | Design review, decision validation, risk assessment |

## Prerequisites

- The user has a proposal, design, or hypothesis to validate
- Relevant context is available (code, docs, requirements)
- For codex mode: the official codex-plugin-cc plugin (`codex@openai-codex`) installed and Codex logged in (checked by `run-codex-role.sh`; exit code 2 otherwise)

## Workflow Phases (methodology)

### Phase 1: Proposal Definition

When the user presents a proposal:

1. **Collect information**:
   - Design documents or specifications
   - Related code and architecture
   - Requirements and constraints
   - Context on why this approach was chosen

2. **Clarify scope**:
   - What specific aspects need validation?
   - What are the known constraints?
   - What alternatives were considered?

### Phase 2: Blue Team Presentation (Claude)

Present and defend the proposal:
- **Clear statement** of what is being proposed
- **Rationale** for why this approach was chosen
- **Benefits** expected from implementation
- **Anticipated concerns** and planned mitigations

### Phase 3: Red Team Critique (Codex/Claude)

Challenge the proposal systematically:
- **Logical flaws** in reasoning
- **Technical risks** and implementation challenges
- **Edge cases** not considered
- **Security, scalability, maintainability** concerns
- **Alternative approaches** that might be better

Concerns are categorized by severity:
- **Critical**: Fundamental flaws that block approval
- **High**: Significant issues requiring changes
- **Medium**: Notable concerns to address
- **Low**: Minor improvements or considerations

### Phase 4: Defense and Refinement (Claude)

Respond to Red Team critique:
- **Address** each concern with reasoning or changes
- **Acknowledge** valid points that require modification
- **Present** refined proposal incorporating feedback
- **Explain** why certain concerns may not apply

### Phase 5: Re-evaluation and Iteration

Red Team reassesses:
- **Acknowledge** adequately addressed concerns
- **Identify** remaining or new issues
- **Prioritize** the most critical unresolved items
- **Continue** until max rounds or consensus

### Phase 6: Final Verdict

After all rounds, Red Team provides:

**APPROVE**: No critical issues, proposal is sound
- Implementation can proceed as designed
- Benefits clearly outweigh remaining risks

**CONDITIONAL**: Proceed with specific conditions
- Implementation can proceed with changes
- Specific conditions must be met
- Follow-up actions may be required

**REJECT**: Fundamental issues require redesign
- Critical flaws undermine the proposal
- Alternative approaches should be considered
- Re-submit after significant revision

## Role Distribution

| Mode | Blue Team | Red Team |
|------|-----------|----------|
| `codex` | Claude | Codex (`red-r<N>`, fresh call per round) |
| `claude-only` | Claude | Claude |

- **Default mode**: `codex`
- **Fallback**: `claude-only` only under the rules in 「実行モード」 (explicit `--mode claude-only`, or exit code 2 with an explicit warning to the user)

## Codex 役の呼び出し

<!-- shared:codex-role-protocol start (4手法で同一。変更時は 4 ファイルすべてに反映する。scripts/lint-plugin.sh の Check 7 が一致を検査) -->

Codex が担当するロールは、プラグイン同梱の `scripts/run-codex-role.sh`（公式 codex-plugin-cc companion の `task --fresh --json` を read-only で 1 回呼ぶラッパー）だけで呼ぶ。`/codex:rescue` や `codex exec` を直接使わない。

**スクリプトの場所**: このスキルの読み込み時に表示される base directory（`.../skills/devils-advocate`）から `<base>/../../scripts/run-codex-role.sh` を組み立てる。`${CLAUDE_PLUGIN_ROOT}` が展開されていればそちらを優先する。

**作業ディレクトリ（対象リポジトリの外）**:

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
echo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG/devils-advocate/<task-id>"
```

- `<state-dir>/state.md` — 手法の状態ファイル（相・終端状態・中断再開用）。frontmatter の `created` は `date -u +%Y-%m-%dT%H:%M:%SZ` の出力をそのまま書く（ローカル時刻に `Z` を付けない）
- `<state-dir>/<role>-<attempt>/` — Codex 呼び出し 1 回分（`attempt` は 1 から）。反復ロールは `<role>-r<round>-<attempt>`
  - `prompt.md` — 送るプロンプト。**1 行目は必ず** `<!-- agent-dialectics-role: devils-advocate/<role> -->`（反復ロールは `<role>-r<round>`）
  - `inputs.json` — prompt.md と同時に Write で書く: `{"method": "devils-advocate", "role": "<role>", "state_sections": ["<state.md の節名>", ...], "artifacts": ["<絶対パス>", ...]}`（prompt 組み立てに使った状態ファイル節と成果物の一覧。非漏洩検査に使う）
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
- claude-only の Red Team は、Blue Team の文脈を持ち込まないよう codex モードと同じ prompt.md（同じ `state_sections`）を Claude サブエージェントに渡して生成するのが望ましい（thread 記録は `claude-subagent-red`）。この場合の APPROVE は「同一モデル内の討論」であり、独立した外部批評を経た承認として報告しない

## Workflow Instructions

### Step 1: Parse Arguments and Initialize

**1. Parse options from `$ARGUMENTS`** (by reading them; no shell parsing needed):
- `--mode codex|claude-only` → mode override (default: `codex`)
- `--max-rounds N` → max rounds (default: `3`)
- The remaining text is the proposal description

Report to the user: mode (and whether user-specified), max rounds, proposal.

**2. Resolve the state dir and task ID:**

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
TASK_ID="$(date +%Y%m%d-%H%M%S)-$RANDOM"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG/devils-advocate/$TASK_ID"
mkdir -p "$STATE_DIR"
echo "ROOT=$ROOT"
echo "TASK_ID=$TASK_ID"
echo "STATE_DIR=$STATE_DIR"
```

Remember `ROOT`, `TASK_ID`, and `STATE_DIR` (shell state does not persist between Bash calls).

**3. Create `<state-dir>/state.md` with the Write tool** (fill in the values; see 「Debate State File」 for the full schema):

```markdown
---
schema: devils-advocate/v2
task_id: <TASK_ID>
created: <ISO-8601 timestamp>
state_dir: <STATE_DIR>
target_root: <ROOT>
proposal: "<proposal>"
mode: <codex|claude-only>
round: 0
max_rounds: <N>
status: in_progress
verdict: pending
degraded: false
codex_call_failures: []
red_thread_ids: []
---

# Red Team Review: <proposal>

## Overview

**Proposal:** <proposal>
**Mode:** <mode>
**Max Rounds:** <N>

## Context

## Snapshot

### Confirmed Points

### Unresolved Concerns

### Rejected Ideas

## Debate Log
```

### Step 2: Gather Context

**Create task:**
- subject: "Gather proposal context"
- description: "Collect design documents, related code, and context for the proposal"
- activeForm: "Gathering context"

**Collect information:**
1. Ask user for any design documents, specifications, or references
2. Identify potentially affected files or components
3. Read relevant code sections
4. Understand the current state and the proposed change

**Fill the `## Context` section of state.md using the Edit tool.** The Red Team cannot read the disk, so include the excerpts (with file paths and line numbers) that the critique needs:

```markdown
## Context

### Proposal Summary
[Brief summary of the proposal]

### Related Files
- file1.ts: Description
- file2.ts: Description

### Relevant Excerpts
[file:line ranges with the excerpted code/doc text the Red Team needs]

### Current State
[Description of how things work currently]

### Proposed Change
[Description of what the proposal aims to change]
```

### Step 3-5: Debate Rounds

Execute debate rounds. Each round follows this pattern:

**Round Structure:**
1. **Blue Team (Claude)**: Present/defend the proposal
2. **Red Team (Codex/Claude)**: Critique and find weaknesses
3. **Update Snapshot and round counter**

**For each round N (1 to max_rounds):**

**Task transition:**
- Mark previous task completed
- Create: "Execute Round N debate"
- activeForm: "Debating round N"

#### Blue Team Phase (Claude)

**Round 1:** Present the proposal with:
- Clear statement of the proposal
- Key benefits and rationale
- Anticipated concerns and mitigations

**Round 2+:** Respond to previous Red Team feedback:
- Address each critique **by concern ID** (every ID listed under `Snapshot/Unresolved Concerns`)
- Present refined proposal
- Acknowledge valid concerns

Append to `## Debate Log` using the Edit tool:

```markdown
### Round N

#### Blue Team (Claude)

**Position:**
[Proposal statement or response to previous critique]

**Key Points:**
1. [Point 1]
2. [Point 2]
3. [Point 3]

**Response to Concerns:**
[If Round 2+, one entry per concern ID: R<k>-C<m> — accepted & changed / rebutted (reason) / deferred (reason)]
```

If Blue declines a Red suggestion (e.g. an alternative approach), add it to `Snapshot/Rejected Ideas` with the reason, marked `(pending Red reassessment)`.

#### Red Team Phase

**If mode = codex:** each round is a **fresh** `red-r<N>` call. Nothing carries over from the previous call except what the prompt re-injects from state.md.

1. Create the attempt dir `<state-dir>/red-r<N>-<attempt>/` (attempt starts at 1; see 再開規則 before creating a new one).
2. Write `prompt.md` with the Write tool using the template below. Paste the state.md sections exactly as listed in the ロール表 for this round.
3. Write `inputs.json` at the same time, e.g. for Round 2:
   ```json
   {"method": "devils-advocate", "role": "red-r2", "state_sections": ["Context", "Snapshot", "Debate Log/Round 1/Red Team", "Debate Log/Round 2/Blue Team"], "artifacts": []}
   ```
4. Run `run-codex-role.sh` with `run_in_background: true` (no `--model` / `--effort` unless the user overrode them), wait for completion, and handle the exit code as in 「Codex 役の呼び出し」.
5. On exit 0: append `- r<N>: codex:<threadId>` to `red_thread_ids`, then run the **acceptance gate** (below) before writing the critique into state.md.
6. On exit 2: warn the user explicitly, record `{role: red-r<N>, exit: 2, attempt: <k>}` in `codex_call_failures`, set `degraded: true`, `mode: claude-only`, and continue this round in claude-only. On exit 4/5: record the failure and ask the user; do not advance the round.

**Critique prompt template (`red-r<N>`)** — the round-specific parts are selected by Claude when writing the file:

````markdown
<!-- agent-dialectics-role: devils-advocate/red-r<N> -->
Respond in <the language of the current conversation>.

You are the Red Team (Devil's Advocate) in a structured debate.

## Constraints

- Do not use web search.
- Do not explore or read the repository. All facts you may rely on are in this prompt (Context excerpts). If a needed fact is missing, say so as an open question instead of assuming.
- Do not modify any files.

## Your Role

Your job is to **critique and challenge** the proposal below. Be thorough but fair.
Focus on finding:
- Logical flaws or gaps in reasoning
- Technical risks or implementation challenges
- Edge cases not considered
- Scalability, security, or maintainability concerns
- Alternative approaches that might be better

## Proposal

<proposal>

## Context

<state.md: Context>

## Snapshot (Round 2+ only)

<state.md: Snapshot — Confirmed Points / Unresolved Concerns / Rejected Ideas>

## Previous Round Red Team Critique (Round 2+ only)

<state.md: Debate Log/Round N-1/Red Team>

## Blue Team Position (Round N)

<state.md: Debate Log/Round N/Blue Team>

## Task

Provide a structured critique of the Blue Team's position.

**Round <N> of <max_rounds> Critique Requirements:**
<Round 1:>
- Initial critique: Identify major weaknesses and risks
- List at least 3 concerns with severity levels (Critical/High/Medium/Low)
- Suggest alternatives or improvements
<Middle rounds (1 < N < max_rounds):>
- Re-evaluate based on Blue Team's responses
- Acknowledge points that have been adequately addressed
- Identify remaining or new concerns
- Prioritize the most important unresolved issues
<Final round (N = max_rounds):>
- Final evaluation: Assess overall proposal quality
- Provide final verdict: APPROVE / CONDITIONAL / REJECT
- List any conditions for approval (if CONDITIONAL)
- Summarize key risks that remain
<Round 2+ (in addition):>
- For EVERY concern ID listed under "Unresolved Concerns" in the Snapshot, state its resolution status in "Prior Findings Status": Resolved / Partially Resolved / Unresolved / Withdrawn, with a one-line reason referring to the Blue Team's response. Do not omit any ID. Do not re-raise a Resolved concern as a new concern.

Label every new concern with an ID `R<N>-C<m>` (m = 1, 2, ...).

## Response Format

```markdown
### Red Team Critique (Round <N>)

#### Prior Findings Status   (Round 2+ only)
| ID | Status | Reason |
|----|--------|--------|
| R<k>-C<m> | Resolved / Partially Resolved / Unresolved / Withdrawn | ... |

#### Key Concerns
1. **R<N>-C1 [Severity: Critical/High/Medium/Low]** [Concern title]
   - Issue: [Description]
   - Impact: [Potential consequences]
   - Suggestion: [Recommended mitigation]

2. ...

#### Open Questions   (non-final rounds) / Final Assessment   (final round)
[Questions for Blue Team OR Final verdict with reasoning]

#### Verdict   (final round only)

**Decision:** [APPROVE / CONDITIONAL / REJECT]

**Reasoning:**
[Explanation of the verdict]

**Conditions (if CONDITIONAL):**
- [Condition 1]
- [Condition 2]

**Remaining Risks:**
- [Risk 1]
- [Risk 2]
```

---
status: stop
verdict: [APPROVE/CONDITIONAL/REJECT]   (final round only)
---
````

Apply the evaluation criteria in 「Evaluation Criteria」 (and `references/evaluation-criteria.md`) for the final verdict; paste the relevant criteria into the final-round prompt.

**Acceptance gate** (run on `answer.md` before writing it into state.md; also applies to claude-only critiques):
- Round 1: at least 3 concerns, each with an ID and severity
- Round 2+: `Prior Findings Status` lists **every** ID that was in `Snapshot/Unresolved Concerns` when the prompt was written, each with one of the four statuses
- Final round: `#### Verdict` with a Decision of exactly APPROVE / CONDITIONAL / REJECT

If the gate fails, do not advance the round and do not re-run automatically: show the user the missing items (e.g. the missing IDs) and ask whether to re-submit as a new attempt (`red-r<N>-<attempt+1>`) or proceed with the gap recorded.

**Record the critique:** append under `### Round N` using the Edit tool:

```markdown
#### Red Team (Codex)

[critique body from answer.md, from "### Red Team Critique" through the end of the Verdict section]
```

**If mode = claude-only:**

Generate the critique with the same prompt.md (preferably via a Claude subagent, see 「実行モード」):
1. Analyze the proposal, Context, Snapshot, and previous round
2. Identify weaknesses, risks, and concerns (with IDs and severities)
3. Provide structured critique, including Prior Findings Status in Round 2+
4. If final round, provide verdict
5. Run the acceptance gate, then append as `#### Red Team (Claude)` using the Edit tool

**Update the Snapshot** (Edit tool) after each Red Team phase, based only on the Red Team's answer:
- `Confirmed Points`: IDs marked Resolved (with one-line summary of how), plus strengths the Red Team acknowledged
- `Unresolved Concerns`: new concerns `R<N>-C<m>` (severity + one line) and IDs marked Unresolved / Partially Resolved
- `Rejected Ideas`: IDs marked Withdrawn (with reason), and Blue-declined suggestions — clear `(pending Red reassessment)` once the Red Team has commented

**Update the round counter** (Edit tool): `round: N-1` → `round: N`.

**Check if debate should continue:** if `round >= max_rounds`, proceed to Step 6; otherwise start Round N+1. If the Red Team reports no unresolved concerns before the final round, you may ask the user whether to conclude early (the final-round prompt, with verdict, is then sent as the next round).

### Step 6: Conclude and Report

**Task transition:**
- Create: "Generate final report"
- activeForm: "Generating report"

**Extract the verdict** from the final Red Team section (`**Decision:**` under `#### Verdict`) and update state.md with the Edit tool: `verdict: pending` → `verdict: <APPROVE|CONDITIONAL|REJECT>` (or `UNKNOWN` if absent — this should already have been caught by the acceptance gate), and `status: in_progress` → `status: completed`. Add a `## Verdict` section with the verdict block.

**Report to user:**

```markdown
## Devil's Advocate Review Complete

**Proposal:** [Original proposal]

**Verdict:** [APPROVE / CONDITIONAL / REJECT]
**Mode:** [codex / claude-only]（degraded: [true/false]）

### Summary

[Brief summary of the debate outcome]

### Key Concerns Raised
1. [R1-C1 Concern 1] - [Status: Resolved/Partially Resolved/Unresolved/Withdrawn]
2. [Concern 2] - [Status]
3. [Concern 3] - [Status]

### Conditions (if CONDITIONAL)
- [Condition 1]
- [Condition 2]

### Remaining Risks
- [Risk 1]
- [Risk 2]

### Recommendations
[Next steps based on the verdict]

### Debate Log
See: <state-dir>/state.md
```

If `degraded: true` or mode was `claude-only`, state clearly that the Red Team was Claude and the verdict is not independent external critique.

### Step 7: Cleanup (Optional)

State dirs are kept outside the target repository for reference and recovery. Do not delete them automatically; if the user wants to clean up, tell them the state dir path.

## Evaluation Criteria

The Red Team uses these criteria for the final verdict (details: `references/evaluation-criteria.md`):

### APPROVE
- No critical or high-severity issues remain
- All major concerns have been adequately addressed
- Implementation is feasible and reasonably safe
- Benefits clearly outweigh remaining risks

### CONDITIONAL
- Implementation can proceed with specific conditions
- Some concerns remain but are manageable
- Specific mitigations or follow-up actions required
- Benefits justify accepting controlled risks

### REJECT
- Critical flaws that fundamentally undermine the proposal
- Major risks that cannot be adequately mitigated
- Alternative approaches are clearly superior
- Implementation would cause significant harm

## Error Handling

**If Codex is unavailable (exit code 2):**
- Follow 「実行モード」: warn the user explicitly, then continue in claude-only with `degraded: true`

**If a Codex call fails (exit code 4/5) or the acceptance gate fails:**
- Do not re-run automatically and do not degrade automatically; show `error.log` or the missing items and ask the user

**If early termination requested:**
- Summarize debate so far
- Provide interim assessment
- Note that full evaluation was not completed (`status: aborted`, `verdict: pending`)

## Debate State File

Debate state is persisted to `<state-dir>/state.md`:

```yaml
---
schema: devils-advocate/v2      # v2: moved to state_dir, fresh Red Team calls, Snapshot
task_id: 20260203-120000-12345
created: 2026-02-03T12:00:00Z
state_dir: /home/user/.local/state/agent-dialectics/my-repo-1a2b3c4d/devils-advocate/20260203-120000-12345
target_root: /home/user/src/my-repo
proposal: "Add caching layer to API responses"
mode: codex
round: 2
max_rounds: 3
status: in_progress             # in_progress | completed | aborted
verdict: pending                # pending | APPROVE | CONDITIONAL | REJECT | UNKNOWN
degraded: false
codex_call_failures: []         # - {role: red-r2, exit: 4, attempt: 1}
red_thread_ids:                 # record only; never used for continuation
  - r1: codex:0199aaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  - r2: codex:0199ffff-1111-2222-3333-444444444444
---

# Red Team Review: Add caching layer to API responses

## Overview

**Proposal:** Add caching layer to API responses
**Mode:** codex
**Max Rounds:** 3

## Context

...

## Snapshot

### Confirmed Points
- R1-C1 (High) Cache invalidation: resolved by cache-aside with explicit invalidation on writes

### Unresolved Concerns
- R1-C2 (Medium) Redis as single point of failure

### Rejected Ideas
- R1-C3 suggestion "use CDN edge caching instead": declined by Blue (responses are per-user)

## Debate Log

### Round 1

#### Blue Team (Claude)

**Position:**
We should add a Redis-based caching layer to reduce database load...

**Key Points:**
1. 80% of requests are read-only and cacheable
2. Expected 60% reduction in DB queries
3. TTL-based invalidation for simplicity

#### Red Team (Codex)

**Key Concerns:**
1. **R1-C1 [Severity: High]** Cache invalidation complexity
   - Issue: Write operations may leave stale data
   - Impact: Users see outdated information
   - Suggestion: Implement cache-aside with explicit invalidation

2. **R1-C2 [Severity: Medium]** Redis as single point of failure
   - Issue: Redis downtime affects entire API
   - Impact: Service degradation
   - Suggestion: Add fallback to direct DB queries

### Round 2

...
```

## Compact Recovery

If compacted during debate:

1. Run `TaskList` to see progress
2. Read `<state-dir>/state.md` (find it under `${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/<slug>/devils-advocate/`; ask the user if several are `in_progress`)
3. Resume from current phase based on state

**State to Phase mapping:**
Check `round >= max_rounds` **first**: if true, go to Step 6 (Conclusion) — never start an extra round. Otherwise:

| State | Resume at |
|-------|-----------|
| `round >= max_rounds` | Step 6 (Conclusion) |
| `round: N` (N < max_rounds) | Step 3 (Round N+1) |

Within a round (`round: N-1`):
- No `### Round N` / Blue Team section → start the Blue Team phase
- Blue Team written, a `red-r<N>-<attempt>/` dir exists → follow 再開規則 in 「Codex 役の呼び出し」 (never resubmit a `DONE` or live `running` attempt)
- Red Team written but round counter not updated → update Snapshot (if not yet) and the round counter

## Safety Guards

The debate process includes:
- **Fair critique**: Red Team should be constructive, not obstructive
- **Severity levels**: Concerns are prioritized appropriately
- **Iteration limits**: Default 3 rounds prevents endless debate
- **Evidence-based**: Critique should cite specific concerns, not vague objections
- **Tracked resolution**: Every concern has an ID and the Red Team states its status each round, so concerns are neither silently dropped nor moved as goalposts

## Output Format

### Progress Display

```
Devil's Advocate Review
=======================
Proposal: Add caching layer to API responses

Round 2 of 3
Status: Blue Team defending

Current concerns:
  [!] R1-C1 High: Cache invalidation complexity (Resolved)
  [?] R1-C2 Medium: Redis SPOF (Pending response)
  [X] R1-C4 Low: Documentation needs (Resolved)
```

### Completion Report

```
Devil's Advocate Review Complete
================================
Proposal: Add caching layer to API responses

Verdict: CONDITIONAL

Summary:
The caching proposal is sound with modifications. Blue Team
adequately addressed invalidation concerns by switching to
cache-aside pattern. Redis SPOF concern requires fallback.

Conditions:
1. Implement fallback to direct DB queries when Redis unavailable
2. Add cache hit/miss metrics for monitoring

Remaining Risks:
- Cache stampede during cold start (Low)
- Memory pressure under high cardinality (Low)

Recommendations:
- Proceed with implementation
- Address conditions before production deployment
- Monitor closely during initial rollout
```

## Invoking the Skill

```
# Basic usage - stress-test a design
/codex-collab:devils-advocate Add a caching layer to reduce database load

# With mode selection
/codex-collab:devils-advocate --mode claude-only Should we migrate to microservices?

# With custom rounds
/codex-collab:devils-advocate --max-rounds 5 This authentication redesign

# Japanese
/codex-collab:devils-advocate この認証設計を批判的にレビューして
```

## Notes

- Debate state is persisted outside the target repository to survive compaction
- Each debate gets a unique task ID and state dir
- Default is 3 rounds but can be customized with `--max-rounds`
- Red Team should be constructive, not adversarial for its own sake

## References

Detailed templates in `references/`:

- **`critique-prompt.md`** - Red Team critique prompt guidelines, round-specific requirements, and severity definitions
- **`evaluation-criteria.md`** - Detailed verdict criteria
