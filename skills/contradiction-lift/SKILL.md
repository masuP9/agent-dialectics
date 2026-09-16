---
name: contradiction-lift
description: 'This skill should be used when the user wants to "synthesize two competing solutions without averaging", "resolve a design/value disagreement by lifting to a higher frame", "止揚 / アウフヘーベン", "矛盾を止揚", "独立案を統合", "平均化せず統合", "contradiction lift", "sublate competing designs", or has two good-but-divergent answers to the same question and wants a higher-order resolution (a selection mechanism) or an honest aporia — not a compromise. NOTE: Use this when two independent solutions diverge and you want to PRESERVE both truth-moments while lifting to a higher frame. Use devils-advocate to stress-test ONE proposal with an assigned opponent, strong-inference to find an unknown cause, and dialectic-loop to validate a claim against a real corpus.'
argument-hint: '[question] [--mode codex|claude-only] [--max-lift-attempts N]'
---

# Contradiction Lift Skill

Have Claude and Codex **independently solve the same problem**, surface the contradiction from where their answers diverge, and pursue **Aufhebung (sublation / 止揚)** — not averaging, not compromise, but a lift that **preserves both truth-moments** while raising them to a higher frame. The output is a **selection mechanism** (when does A win, when does B win, and why) or an **honest aporia** (this cannot be lifted; here is the irreducible axis).

## Question

$ARGUMENTS

## Overview

The single most important design fact: **the enemy of Aufhebung is not conflict — it is averaging** (a watered-down middle ground). Left alone, two LLMs fail in two ways: premature agreement (mutually sycophantic "great point, I agree" → instant collapse), or sterile gridlock (debate where each just re-states its position). Telling them to "find the middle" produces the worst outcome — a diluted average. So almost the entire mechanism is spent **keeping the process out of averaging and out of gridlock, and forcing a real lift**.

A Contradiction Lift run:

1. **Fixes the question** (Decision Contract) so interpretation gaps are not mistaken for contradictions.
2. **Seals two independent solutions** — a fresh Claude subagent (Solver A) and Codex (Solver B) solve **in parallel**; the orchestrator dispatches both and reads neither until both return, so sealing is **structural** (the orchestrator never authors a solution it could contaminate).
3. **Maps the divergence** by type and names the **load-bearing** premises (flip-test).
4. **Routes** each disagreement: empirically decidable → Codex runs a *discriminating* experiment; the rest → preservation.
5. **Preserves** each side via mutual steelman (accept / repair-once handshake).
6. **Constructs a lift** — a selection mechanism `f(C) → A | B | N`, not a position.
7. **Audits the lift** against 7 tests; if it fails twice, declares an honest aporia.

## 利用量ポリシーとロール表

1. **Codex 役は常に fresh**。反復（ラウンド、再レビュー）は「前回までの要約（確定事項・未解決・却下案）+ 必要な抜粋」を含む自己完結プロンプトで再投入する。thread を継続しない
2. **事実はプロンプトに持たせる**。Claude 側で読んだファイル抜粋・行番号・確認済み事実を prompt.md に入れる。「リポジトリを探索して検証せよ」とは指示しない。ディスク読取を許すのは、下表で「読取が役割」と宣言したロールだけ
3. **Web 検索は使わない**よう、全ロールの prompt に明記する
4. **入力トークン上限**: 1 呼び出しあたり 10 万トークン。超えたらプロンプトを見直す（例外は下表で個別上限を宣言したロールのみ）

| ロール（attempt ディレクトリ名） | 担当 | `--model` / `--effort` | ディスク読取 | 入力上限 |
|---|---|---|---|---|
| Solver A | fresh Claude subagent（Task） | — | 可（Decision Contract の `### Referenced files` に列挙したファイルのみ） | — |
| Solver B（`solver-b`） | Codex | 既定（config.toml） | 可（`### Referenced files` のみ。封印解テンプレートの "Re-read referenced files" に対応） | 10 万 |
| Mapper（`mapper`） | Codex **または** fresh Claude subagent | Codex 時 `--model gpt-5.6-luna --effort low` | 可（`### Referenced files` のみ） | 10 万 |
| Empirical Arbiter（`arbiter-d<k>`、k = Ledger の番号） | Codex | 既定（config.toml） | 可（判別実験に必要な範囲。書き込み不可） | 10 万 |
| Preservation party B（`preserve-b-steelman` / `preserve-b-review` / `preserve-b-repair` / `preserve-b-rereview`） | Codex（Solver B 側の当事者） | 既定（config.toml） | 不可 | 10 万 |
| Preservation party A | fresh Claude subagent（Task） | — | 不可 | — |
| Lift Architect（`lift-r<n>`、n = 今回の lift attempt 番号） | Codex **または** fresh Claude subagent | Codex 時 既定（config.toml） | 不可 | 10 万 |
| Meta Auditor（`audit-r<n>`） | Lift Architect と**逆のモデル**を優先 | Codex 時 既定（config.toml） | 不可 | 10 万 |

ユーザーは実行時にこの表の model / effort を上書きできる（例: 「mapper は既定モデルで」）。

### Non-leak allowlists (checked against `inputs.json` `state_sections`)

Every Codex role's `inputs.json` `state_sections` MUST be a subset of its allowlist below. Section names are the literal `state.md` headings (`<parent>/<child>` for `###` subsections). `<a>` / `<b>` are the anonymized labels of Solution A / Solution B from `anonymization_key` (e.g. `X=A,Y=B` → `<a>`=X, `<b>`=Y). **No Codex role ever receives `Sealed Solutions/*`** (they carry model identity; the orchestrator reads them only to produce `Anonymized Solutions`), and the frontmatter (including `anonymization_key`) is never pasted into a prompt.

| Codex role | Allowed `state_sections` | Explicitly forbidden (examples) | `artifacts` |
|---|---|---|---|
| `solver-b` | `Decision Contract` | `Sealed Solutions/Solution A (Claude)`, `Anonymized Solutions/*`, everything after the contract | `references/sealed-solution-template.md` + files under `### Referenced files` |
| `mapper` | `Decision Contract`, `Anonymized Solutions/Solution X`, `Anonymized Solutions/Solution Y` | `Sealed Solutions/*` (non-anonymized, model-identified), any later section | `references/divergence-map-template.md` + `### Referenced files` |
| `arbiter-d<k>` | `Decision Contract`, `Divergence Ledger`, `Adjudication` | `Sealed Solutions/*`, `Preservation`, `Lift`, `Audit` | target files needed for the experiment |
| `preserve-b-steelman` | `Decision Contract`, `Anonymized Solutions/Solution <b>`, `Anonymized Solutions/Solution <a>`, `Divergence Ledger`, `Adjudication` | `Sealed Solutions/*`, `Preservation/<a>-steelmans-<b>` (the other party's steelman must not anchor B's) | — |
| `preserve-b-review` / `preserve-b-rereview` | `Decision Contract`, `Anonymized Solutions/Solution <b>`, `Preservation/<a>-steelmans-<b>` | `Sealed Solutions/*`, `Anonymized Solutions/Solution <a>`, `Preservation/<b>-steelmans-<a>` | — |
| `preserve-b-repair` | `Decision Contract`, `Anonymized Solutions/Solution <b>`, `Anonymized Solutions/Solution <a>`, `Preservation/<b>-steelmans-<a>`, `Preservation/Review of <b>-steelmans-<a>` | `Sealed Solutions/*` | — |
| `lift-r<n>` | `Decision Contract`, `Anonymized Solutions/Solution X`, `Anonymized Solutions/Solution Y`, `Divergence Ledger`, `Adjudication`, `Preservation`; for n ≥ 2 also `Lift/Attempt <n-1>`, `Audit/Attempt <n-1>` | `Sealed Solutions/*` | `references/lift-audit-template.md` |
| `audit-r<n>` | `Decision Contract`, `Anonymized Solutions/Solution X`, `Anonymized Solutions/Solution Y`, `Divergence Ledger`, `Adjudication`, `Preservation`, `Lift/Attempt <n>` | `Sealed Solutions/*`, `Audit/*` (no anchoring on earlier audits), `Lift/Attempt <m≠n>` | `references/lift-audit-template.md` |

Claude-subagent roles follow the **same allowlists** (Solver A: `Decision Contract` only; the Claude-side party mirrors the B-side rows with `<a>`/`<b>` swapped). Before each Codex run, check `inputs.json` against this table; a violation is a caller error — fix the prompt in a **new attempt** rather than running it.

**Prompt boilerplate** (every role, Codex or subagent): the first line after the role marker states "Respond in the language of the user's conversation (<language>)." and "Do not use web search." Where a reference template contains `{{LANG_DIRECTIVE}}`, put that language line there. Codex roles whose table row says ディスク読取 不可 additionally get "Do not read files from disk; use only the material in this prompt."

## Comparison with sibling skills

| Aspect | Strong Inference | Devil's Advocate | Dialectic Loop | **Contradiction Lift** |
|--------|------------------|------------------|----------------|------------------------|
| Purpose | Find an unknown cause | Stress-test one proposal | Validate/refine a claim vs data | **Lift two divergent solutions to a higher frame** |
| Contradiction | competing hypotheses | **assigned** (external red team) | prediction vs evidence | **emergent** (two independent solves diverge) |
| Engine of truth | decisive experiment | adversarial critique | counterexample hunting on corpus | **preservation + lift, with empirical routing** |
| Output | root cause | verdict (APPROVE/…) | refined hypothesis H′ | **selection mechanism, or honest aporia** |
| Success ≠ | — | — | — | **agreement, average, residual-shrink** |
| Best for | debugging | validating a design | trend/claim checking | design/value/direction calls where one experiment can't settle it |

## Prerequisites

- A question with **multiple reasonable decision rules** that a single experiment cannot fully settle (design trade-offs, API/architecture philosophy, product direction, abstraction boundaries). Composite problems are welcome: empirical sub-parts are routed to Codex, and the residual normative core is lifted.
- For `codex` mode: the plugin's `scripts/run-codex-role.sh` must be able to reach Codex (codex-plugin-cc companion installed, Codex CLI installed and logged in). Independence (two *different* models) is the whole point — see Role Distribution.

## Design principles (lessons baked in)

1. **Averaging is the enemy, not conflict.** Never optimize for agreement, average, or residual-shrink. A diluted middle ground is failure, even when it looks like consensus.
2. **Do not pre-assign positions.** Unlike Devil's Advocate (external opponent), let both models *independently* solve the same problem and raise the contradiction from the divergence. Strict ordering: **solve sealed, then reveal** — showing the other's answer first collapses the divergence into anchoring. **Sealing is structural, not disciplinary:** the orchestrator must not author Solution A itself (while orchestrating it would already have seen Solver B). Solver A runs as a **fresh Claude subagent**, dispatched **in parallel** with Solver B (Codex); the orchestrator reads neither until both are sealed. The orchestrator's job is dispatch / anonymize / route / persist — never solve or synthesize.
3. **Name the contradiction before lifting.** The real conflict is usually at the level of an unstated **load-bearing premise**, not the surface conclusion. Surfacing that premise is half of the lift.
4. **Force the preservation moment.** Before lifting, each side must steelman the other in full (Aufhebung's "preserve"), then identify the **irreducible incompatible core** that survives mutual steelman. Averaging fails because it merges before isolating this residual.
5. **Let the object adjudicate what it can.** Empirically decidable disagreements are *not debated* — Codex runs a **discriminating** experiment (pre-register "if X then A, if Y then B" before running). The object (code/data) asserts itself. Only execution-undecidable disagreements go to the lift.
6. **A third role must be separate from the parties.** Letting a party synthesize produces sycophantic averaging. Mapping, lift construction, and audit run on **fresh, anonymized roles** — either a **fresh Claude subagent** (own context window, no reasoning history) or a **fresh Codex call**. Pick the assignee by *which independence the role needs* (see "Independence: two kinds"): subagents buy **context-independence**; only the Claude/Codex split **approximates prior-independence** (different model family — never a full guarantee).
7. **Allow an honest aporia.** Forcing a synthesis when none exists disguises an average as a "synthesis". If the trade-off is genuinely irreducible, "this cannot be lifted; the axis is X" is worth more than a fake third term. This escape is the last guard against fleeing into averaging.

## Independence: two kinds

Every non-party role needs *some* independence, but there are **two distinct kinds**, and they come from different places:

| Kind | What it prevents | Source |
|------|------------------|--------|
| **Context-independence** | sealing breaches, anchoring, orchestrator contamination, history leakage | a **fresh context** — a Claude **subagent** (own window, no reasoning history) *or* a fresh Codex call |
| **Prior-independence** | *correlated blind spots* — two solvers from the same training distribution making the same error and "agreeing" | a **different model family** — approximated (not guaranteed) by the **Claude × Codex** split; shared training data/eval practices mean overlap can remain |

The consequences for role assignment:

- **Solvers (Phase 1) need prior-independence** — the engine is *two different priors diverging* as a liftability detector. Keep **Solver A = Claude subagent, Solver B = Codex**. (Same-model two-pass is the degraded `claude-only` mode.) Subagents additionally make the seal structural (parallel dispatch, orchestrator reads neither first).
- **Verification roles (Mapper, Lift Architect, Auditor) need context-independence first** — a fresh subagent or Codex call, anonymized, no history. They additionally benefit from **cross-model pairing**: audit a Claude-built lift with a **Codex** auditor and a Codex-built lift with a **Claude** auditor, so a correlated blind spot is **far less likely** to pass both build and audit. A **same-model agreement** (two instances of one model — e.g. the orchestrator and a Claude subagent — reaching the same answer) is **not** independent evidence: shared priors correlate their errors, so never treat "the subagent agreed" as confirmation.

## Codex 役の呼び出し

<!-- shared:codex-role-protocol start (4手法で同一。変更時は 4 ファイルすべてに反映する。scripts/lint-plugin.sh の Check 7 が一致を検査) -->

Codex が担当するロールは、プラグイン同梱の `scripts/run-codex-role.sh`（公式 codex-plugin-cc companion の `task --fresh --json` を read-only で 1 回呼ぶラッパー）だけで呼ぶ。`/codex:rescue` や `codex exec` を直接使わない。

**スクリプトの場所**: このスキルの読み込み時に表示される base directory（`.../skills/contradiction-lift`）から `<base>/../../scripts/run-codex-role.sh` を組み立てる。`${CLAUDE_PLUGIN_ROOT}` が展開されていればそちらを優先する。

**作業ディレクトリ（対象リポジトリの外）**:

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
echo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG/contradiction-lift/<task-id>"
```

- `<state-dir>/state.md` — 手法の状態ファイル（相・終端状態・中断再開用）。frontmatter の `created` は `date -u +%Y-%m-%dT%H:%M:%SZ` の出力をそのまま書く（ローカル時刻に `Z` を付けない）
- `<state-dir>/<role>-<attempt>/` — Codex 呼び出し 1 回分（`attempt` は 1 から）。反復ロールは `<role>-r<round>-<attempt>`
  - `prompt.md` — 送るプロンプト。**1 行目は必ず** `<!-- agent-dialectics-role: contradiction-lift/<role> -->`（反復ロールは `<role>-r<round>`）
  - `inputs.json` — prompt.md と同時に Write で書く: `{"method": "contradiction-lift", "role": "<role>", "state_sections": ["<state.md の節名>", ...], "artifacts": ["<絶対パス>", ...]}`（prompt 組み立てに使った状態ファイル節と成果物の一覧。非漏洩検査に使う）
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

**Actor keys and comparisons (this skill).** `meta.json` keeps the raw UUID. In `state.md`, every `*_thread_id` holds `codex:<uuid>` (Codex role) or `claude-subagent-<role>` (Claude subagent); these are **records only** and are never used to continue a conversation. Any distinctness / cross-model check compares the **raw value with the `codex:` prefix stripped** (e.g. `audit_thread_id ≠ lift_thread_id`, `mapper_thread_id ≠ solver_b_thread_id`); a role is "Codex" iff its actor key starts with `codex:`.

## 実行モード

- `codex`（既定）: Codex 役を `run-codex-role.sh` で呼ぶ
- `claude-only`: `--mode claude-only` の明示指定時、または `run-codex-role.sh` が **終了コード 2** を返したときに、**ユーザーに明示的に警告したうえで**縮退する
- **縮退時の警告は、縮退した時点で出す（必須）**: 終了コード 2 を受け取ったら、**次のツール呼び出し（Claude サブエージェントの起動、状態ファイルの更新を含む）より前に**、ユーザー向けのテキストとして次の警告を出す。最終レポートの注記や「Claude のサブエージェントに書かせています」のような途中経過の説明では代わりにならない。理由は完了通知など取得済みの情報から書き、未取得なら「詳細未確認」とする（理由を調べるためのツール呼び出しは警告のあとで行い、必要なら補足する）

  > ⚠️ Codex を使えないため（`run-codex-role.sh` 終了コード 2: `<error.log の理由を 1 行>`）、`<role>` 以降を Claude だけで続けます（`degraded: true`）。別モデルによる独立した確認がないため、結論の確かさは下がります。cross-model でなくなるロール: `<ロール名の一覧>`
- 状態ファイルに `degraded: true|false` と `codex_call_failures`（`- {role, exit, attempt}` のリスト）を分けて記録する
- 終了コード 4 / 5 は縮退理由にしない（自動再実行も自動縮退もしない。ユーザー判断）
- 同一モデル（Claude が Claude の結論を確認）の一致を独立した裏付けに数えない
- **contradiction-lift 固有の縮退規則**:
  - `claude-only` では Solver B が 2 体目の fresh Claude subagent になり、**どのロールも cross-model にできない**（context-independence のみ。二つの異なるモデルが分岐するというエンジンが失われる）。警告し、`codex` モードを推奨する
  - 終了コード 2 で縮退した場合も、**cross-model であるべきロール**（Solver B、Lift Architect と逆モデルの Auditor）が cross-model でなくなったことを警告とレポートに明記する。黙って縮退しない
  - **Task tool も使えない**場合、Solver B を cross-context に作れないので**停止**する（同一コンテキストの著者 1 人では封印も独立もない。第二の解を捏造しない）
  - 終了コード 4 / 5 の後にユーザーが「そのロールを Claude subagent で」と選んだ場合のみ subagent に切り替え、`degraded: true` と独立性の注記（same-prior）を残す。Task tool も無ければ停止し、`state` は最後の有効値のまま、run を未完了として報告する

## Workflow

State machine: `contract → sealed → mapped → adjudicated → preserved → lifted → accepted | aporia`. A third terminal, `no_material_divergence`, can be reached from `mapped` (see Phase 2) — used when the two solutions share the same load-bearing core, so there is nothing to lift.

> **All Task-dispatched roles** (Solver A, Solver B in claude-only, Mapper, Lift Architect, Meta Auditor, and the Phase 4 Claude-side party) carry the **same analysis-only constraint** — no file writes (prefer a read-only subagent type such as `Explore` where available); they return their artifact as the final message and the **orchestrator** records it into `state.md`.

### Step 1: Parse Arguments and Initialize

1. **Parse options** from the Question above: `--mode <codex|claude-only>`, `--max-lift-attempts <N>` (default 2). The remainder is the question `Q`.
2. **Determine mode**: default `codex`; honor `--mode`. Codex availability is discovered by the first `run-codex-role.sh` call (exit 2 → degrade per 実行モード). In `claude-only`, **warn** that independence is weak (the core is two *different* models diverging) and recommend `codex`.
3. **Scope check**: this skill is for questions where multiple reasonable decision rules remain and a single experiment can't settle the whole. If the question is a plain bug / perf comparison / spec-conformance, suggest `/agent-dialectics:strong-inference`; if it's stress-testing one proposal, suggest `/agent-dialectics:devils-advocate`; if it's a claim-vs-data check, suggest `/agent-dialectics:dialectic-loop`.
4. **Generate the task id** (`YYYYMMDD-HHMMSS-<random>`), compute `<state-dir>` (Codex 役の呼び出し), `mkdir -p` it, and write `<state-dir>/state.md` with the `contradiction-lift/v3` schema (see State File) using Write. Set `state: contract`, `degraded: false`, `codex_call_failures: []`.

### Step 2: Phase 0 — Decision Contract

Fix the shared frame **first**: the question `Q`, success conditions, constraints, immovable requirements, empirically observable variables, and the required decision format. If this is vague, a mere interpretation gap will be mis-read as a philosophical contradiction. Write it to `## Decision Contract`; list under `### Referenced files` the repository files (absolute paths) the solvers may read, and paste short excerpts of anything the orchestrator already confirmed. **Confirm with the user.** Keep `state: contract`.

### Step 3: Phase 1 — Sealed Solutions (Claude + Codex, independent, parallel)

Both solvers answer `Q` against the **same Decision Contract**, **sealed** (neither sees the other). Each uses `references/sealed-solution-template.md` and submits the **decision function, not just a conclusion**: conclusion, decision rule, causal model, load-bearing assumptions, invariants to protect, rejected alternatives, the observation that would flip the conclusion, confidence.

**Dispatch Solver A and Solver B in the same message, then read both.** The orchestrator must **not** author Solution A itself — by the time it has dispatched Solver B it is contaminated.

- **Solver A = fresh Claude subagent (Task tool)** — prompt built only from `Decision Contract` + the sealed-solution template:
  ```
  Task(
    subagent_type: "general-purpose",   // prefer a read-only type (e.g. "Explore") where available
    description: "Sealed Solver A",
    prompt: "<language + no-web-search lines><Decision Contract + sealed-solution-template>. Solve independently and return ONLY the filled template as your final message. Analysis only: do NOT edit/write/commit any files, and do not reference any other solution."
  )
  ```
  Record the result under `### Solution A (Claude)`; keep `solver_a_role: claude-subagent`.
- **Solver B — by `mode`:**
  - `mode: codex` → Codex role `solver-b`. Write `<state-dir>/solver-b-1/prompt.md` (role marker `contradiction-lift/solver-b`, boilerplate, Decision Contract, sealed-solution template — **NEVER Solution A**) and `inputs.json` with `state_sections: ["Decision Contract"]`, then run `run-codex-role.sh` in the background (default model). On exit 0 record `solver_b_thread_id: "codex:<uuid>"` and write `answer.md` under `### Solution B (Codex)`.
  - `mode: claude-only` (or exit 2 → degrade) → a **second fresh Claude subagent** with the same prompt constraints as Solver A (built from `Decision Contract` only — not from anything Solver A returned); `solver_b_thread_id: claude-subagent-solverB`; write under `### Solution B (Claude #2)`. Warn that independence is context-only (same prior).
  - Exit 4 / 5 → ask the user (new attempt / Claude subagent with same-prior caveat / stop).
- **Sealing guards:** dispatch both before reading either; never put Solution A into Solver B's prompt (or vice versa); the orchestrator authors neither.
- **Fallback — no Task tool:** the orchestrator authors Solution A **first**, while still blind to Solver B, **persists it** to `state.md` with `solver_a_role: orchestrator-fallback`, and only **then** starts `solver-b` (safe because A is already sealed). Authoring A *after* seeing B is forbidden. Note in the report that sealing was disciplinary, not structural. **No Codex *and* no Task tool** → stop (see 実行モード).

**Anonymize** once both are sealed: pick the X/Y assignment at random, record it in frontmatter `anonymization_key` (e.g. `"X=B,Y=A"`), and write `## Anonymized Solutions` → `### Solution X` / `### Solution Y` with the solution bodies stripped of any self-identifying wording (model names, "as Codex", etc.). From here on, every later section uses **X / Y** labels only.

Set `state: sealed`.

### Step 4: Phase 2 — Divergence Mapping (anonymized)

A fresh role **distinct from Solver B** builds a disagreement ledger with `references/divergence-map-template.md`, from the anonymized X / Y only:

- **Codex option** (`mapper_role: codex-thread`): role `mapper`, `--model gpt-5.6-luna --effort low`, `state_sections: ["Decision Contract", "Anonymized Solutions/Solution X", "Anonymized Solutions/Solution Y"]`. Record `mapper_thread_id: "codex:<uuid>"` and verify its raw UUID ≠ the raw UUID of `solver_b_thread_id`.
- **Subagent option** (`mapper_role: claude-subagent`, `mapper_thread_id: claude-subagent-mapper`):
  ```
  Task(subagent_type: "general-purpose", description: "Divergence Mapper",
       prompt: "<boilerplate><contract + anonymized X/Y; build the typed disagreement ledger with flip-test>. Analysis only: do NOT edit/write/commit files; return the ledger as your final message.")
  ```

- Type each disagreement (`semantic|empirical|causal|normative|constraint|uncertainty`) and mark **load-bearing** ones via the **flip-test** (flip only that premise — does the conclusion/decision rule change?).
- Append `## Divergence Ledger`; set `state: mapped`.
- **No material divergence:** if the ledger has **no load-bearing disagreement**, set `state: no_material_divergence` and `outcome: no_material_divergence` (no lift attempted), and report that both solutions share the load-bearing core. **Do not fabricate a contradiction** — skip to Step 9.

### Step 5: Phase 3 — Adjudication Router

Route each disagreement and append `## Adjudication`:

- **empirical / observable** → **pre-register** "if result X → A, if Y → B" in `## Adjudication` **first**, then run a **discriminating** experiment (not "run anything") as Codex role `arbiter-d<k>` (default model; `state_sections: ["Decision Contract", "Divergence Ledger", "Adjudication"]`; the prompt names the files/commands it may read or run **read-only**). Record the result and the actor key `codex:<uuid>` under the pre-registration. Set `empirical_arbiter: done` when finished. `run-codex-role.sh` is always read-only: if the discriminating experiment **must build/run with writes**, do not work around it — ask the user whether they will run it themselves (record the result as user-provided) or mark it deferred (below). In `claude-only`, the arbiter is a fresh analysis-only Claude subagent (read-only commands only).
- **semantic** → normalize the term, dissolve the disagreement.
- **constraint** → check against the Decision Contract.
- **normative / unobservable-causal** → carry forward to Preservation.

If there are **no empirical disagreements** to run, set `empirical_arbiter: not_applicable` (not `pending`). If an empirical disagreement **exists but its discriminating experiment cannot be run this session** (e.g., no benchmark/corpus available, or it needs writes the user will not perform), still **pre-register** the experiment, set `empirical_arbiter: deferred`, and carry the residual to the lift **conditionally on that observable** (do not guess the result). Set `state: adjudicated`.

### Step 6: Phase 4 — Preservation Contract (mutual steelman, accept/repair-once)

For the disagreements that remain, each party submits, about the **other**: the conditions under which the other's solution is strongest; the truth-moment lost if it is discarded; a concrete failure of the design without that moment; and the incompatible core that still remains. The other party reviews with **`accept` / `repair once`** only — no unbounded handshake (review = "is my reasoning represented faithfully?", not "do I agree?").

**Party continuity across phases.** Neither party has a continued conversation. Both sides are **fresh calls re-seeded from the persisted record**: the Codex side (party B, label `<b>`) is a fresh `run-codex-role.sh` call whose prompt re-injects `Anonymized Solutions/Solution <b>` (its own recorded solution — "your recorded solution is labeled `<b>`") plus the step's target text from `state.md`; the Claude side (party A, label `<a>`) is a fresh Claude subagent re-seeded the same way. Identity is reconstructed from the record, which is sufficient because steelman/review depend only on the *recorded* decision function and assumptions, not on private reasoning.

`## Preservation` subsections: `### <a>-steelmans-<b>`, `### <b>-steelmans-<a>`, `### Review of <a>-steelmans-<b>` (by `<b>`), `### Review of <b>-steelmans-<a>` (by `<a>`), `### Repairs`, `### Certification`. Record each call's actor key (`codex:<uuid>` / `claude-subagent-preserveA`) next to its output.

**The orchestrator mediates a 4-substep handshake** (each step's output is the next step's input):

1. **Steelman (both sides, parallel).**
   - Claude side → fresh subagent seeded with `Decision Contract`, `Anonymized Solutions/Solution <a>` (own), `Anonymized Solutions/Solution <b>`, `Divergence Ledger`, `Adjudication`: "Steelman the OTHER side (`<b>`). Output only the steelman." → `### <a>-steelmans-<b>`.
   - Codex side (`mode: codex`) → role `preserve-b-steelman` (allowlist above; it must not see `<a>-steelmans-<b>`) → `### <b>-steelmans-<a>`.
2. **Cross-review (accept / repair-once).** Each steelman goes to the party it is *about*:
   - `<a>-steelmans-<b>` → role `preserve-b-review` (`Solution <b>` + that steelman): "Is your reasoning represented faithfully? Reply `accept` or `repair once` (with what is misrepresented)." → `### Review of <a>-steelmans-<b>`.
   - `<b>-steelmans-<a>` → fresh Claude subagent seeded with `Solution <a>` + that steelman: same prompt → `### Review of <b>-steelmans-<a>`.
3. **Repair once (if requested).** The repair request goes back to the **original steelman author** for **one** revision, then one re-review:
   - Repair of `<b>-steelmans-<a>` → role `preserve-b-repair` (its steelman + the review) → revised text appended under `### <b>-steelmans-<a>` (marked "revised") and noted in `### Repairs`; re-review by a fresh Claude subagent.
   - Repair of `<a>-steelmans-<b>` → fresh Claude subagent → revised text; re-review by role `preserve-b-rereview` (`Solution <b>` + the revised steelman).
4. **Record.** `accept` → the truth-moment is conserved; **still not accepted after the one repair → mark it `uncertified`** in `### Certification` (it will fail the Audit's Conservation test → `aporia`).

**By mode / fallback:**
- `mode: claude-only` → every Codex step above becomes a fresh re-seeded Claude subagent (`claude-subagent-preserveB`) with the same allowlists; warn that reviews are same-prior.
- **No Task tool** → the orchestrator performs the **Claude-side** steelman and review itself (degraded — the documented Phase-4 exception; note it in the report); the Codex side still runs as fresh `preserve-b-*` calls.
- Any `preserve-b-*` call: exit 4 / 5 → ask the user; no automatic retry.

Append `## Preservation`; set `state: preserved`.

- **If a steelman is still not accepted after the single repair:** do **not** silently proceed. Record the contested truth-moment as **uncertified**. An uncertified load-bearing moment cannot be conserved, so it will fail the Audit's **Conservation** test → the run resolves to `aporia` (the parties cannot even agree on what the other is preserving). Carry it forward so the audit sees it.

### Step 7: Phase 5 — Lift Construction (anonymized, fresh role)

Determine the attempt number from disk, not from a counter: `n` = (number of **completed** audits, i.e. `### Attempt` entries under `## Audit` that contain a recorded 7-test result) + 1; an empty heading does not count. Do **not** increment anything before the call — an interrupted Step 7 must resume the same `lift-r<n>` (follow the 再開規則 for an existing `lift-r<n>-<attempt>` directory) instead of consuming a new reconstruction. Set `lift_attempts: n` only when `## Lift` → `### Attempt <n>` is written below. Delegate to a **fresh** "Lift Architect" — a Claude subagent (`lift_role: claude-subagent`, `lift_thread_id: claude-subagent-lift`) or Codex role `lift-r<n>` (`lift_role: codex-thread`, default model, `lift_thread_id: "codex:<uuid>"`) — using `references/lift-audit-template.md`, with the `lift-r<n>` allowlist. For `n ≥ 2`, the prompt is self-contained: include `Lift/Attempt <n-1>` and `Audit/Attempt <n-1>` (which tests failed and why) and ask for a reconstruction, not a patch.

Build a **selection mechanism** `f(C) → A | B | N` (A = X's answer, B = Y's, as in the template), not a position. Required: conserved moments of both; any **new** variable/relation; an example selecting A, one selecting B, and **one differing from a simple average**; failure conditions; the causal mechanism. `Q'` is optional (a threshold/ordering/option-value/reversibility-staged decision also counts). Append `## Lift` → `### Attempt <n>`; set `state: lifted`.

### Step 8: Phase 6 — Lift Audit (independent role)

Delegate the audit to an **independent** role that did **not** build the lift, with the `audit-r<n>` allowlist. **Prefer cross-model pairing**: if `lift_role: claude-subagent`, run the audit as Codex role `audit-r<n>` (default model, `audit_role: codex-thread`, `audit_thread_id: "codex:<uuid>"`); if `lift_role: codex-thread`, run it on a **fresh Claude subagent** (`audit_role: claude-subagent`, `audit_thread_id: claude-subagent-audit`). Verify raw `audit_thread_id ≠` raw `lift_thread_id` — the per-role sentinels **record** this distinctness even when both are Claude subagents (`claude-subagent-audit ≠ claude-subagent-lift`); it is a procedural record, not a runtime proof, so always dispatch a **new** subagent/call per role. If the Codex audit cannot run (exit 2), the audit falls back to a Claude subagent **with an explicit warning** that the audit is no longer cross-model (`degraded: true`); exit 4 / 5 → ask the user.

Run all **7 tests** and demand the **causal mechanism** ("why does that condition change the choice?"). Append `## Audit` → `### Attempt <n>`.

- **All 7 pass AND causal check = yes** → `outcome: lifted`, `state: accepted` → Step 9. (A 7/7 with `causal check = no` does **not** pass — a mechanism-less router is not a lift.)
- **Any fail** and `lift_attempts < max_lift_attempts` → return to **Step 7** (reconstruct once).
- **Any fail** and `lift_attempts >= max_lift_attempts` → `outcome: aporia`, `state: aporia` → Step 9.

**The 7 tests** (these close the holes: a useless new variable, fabricated scenarios, a mere condition-branch router masquerading as a lift):

1. **Conservation** — the conserved moments of both A and B are traceable.
2. **Discrimination** — the mechanism actually selects differently under different conditions.
3. **Novelty** — there is a decision variable / relation / procedure absent from both originals.
4. **Non-vacuity** — it does not end at "it depends"; the conditions are observable.
5. **Dominance** — in at least one scenario it out-explains/out-decides A, B, **and** the simple compromise.
6. **Falsifiability** — you can state the conditions under which the lift fails.
7. **Feasibility** — the application cost does not eat the benefit.

### Step 9: Conclude and Report

Report using the **Output Format** below — **Accepted lift**, **Honest aporia**, or **No material divergence** — and point to `<state-dir>/state.md`. Include `degraded`, any `codex_call_failures`, and every independence degradation (claude-only, non-cross-model audit, orchestrator fallback).

## Role Distribution

The **orchestrator** (the Claude session running this skill) is dispatch-only: it fixes the contract, dispatches roles, anonymizes inputs, routes, persists state, and reports. It **never** authors a solution, a steelman, a lift, or an audit — those all run in fresh roles.

| Role | Assignee | Notes |
|------|----------|-------|
| Solver A | **fresh Claude subagent** (Task tool, analysis-only) | sealed; dispatched in parallel with Solver B; **not** the orchestrator |
| Solver B | Codex (`solver-b`, fresh, read-only) | sealed; never sees A first |
| Mapper | fresh Claude subagent **or** Codex (`mapper`, anonymized X/Y) | typed divergence + flip-test |
| Empirical Arbiter | Codex (`arbiter-d<k>`, read-only) | pre-registered discriminating experiments; write-requiring experiments → user-run or deferred |
| Preservation parties | A side: fresh Claude subagent; B side: Codex (`preserve-b-*`) | re-seeded from the record each call |
| Lift Architect | fresh subagent **or** Codex (`lift-r<n>`, anonymized) | builds the selection mechanism |
| Meta Auditor | independent role that did **not** build the lift — **prefer the opposite model** to the Architect (`audit-r<n>` when Codex) | 7-test audit; cross-model where possible |

**Honest limitation on independence.** A Claude subagent gives **context-independence** (fresh window, no history) but **not prior-independence** — it shares Claude's training distribution, so Claude-subagent roles can carry the same blind spots as the orchestrator. Stronger (still imperfect) prior-independence comes from the **Claude × Codex** split — different model families, though shared training data/eval practices mean overlap can remain. Therefore: keep solvers cross-model, and **pair verification across models** (Claude-built lift → Codex audit, and vice versa) to reduce — not eliminate — correlated errors. Where a role cannot be cross-model (e.g. `claude-only` mode, exit-2 degradation, or no Task tool), say so plainly and **do not treat a same-model agreement as confirmation**.

- **Default mode**: `codex` (independence of two different models is the design goal). Solver A = Claude subagent, Solver B = Codex; verification roles can be cross-model.
- **`claude-only` mode**: degraded — Solver B becomes a **second fresh Claude subagent** (`solver_b_thread_id: claude-subagent-solverB`), and **no role can be cross-model**, so only context-independence is available. The subagents still keep sealing structural and avoid anchoring, but treat agreement with extra suspicion. Warn explicitly and recommend `codex` mode.
- **No Task tool** (subagents unavailable): Solver A falls back to the orchestrator (`solver_a_role: orchestrator-fallback`), authored **first** while still blind to Solver B and **persisted**, **then** Solver B is dispatched. Authoring A *after* seeing B is forbidden. Sealing degrades from structural to **disciplinary**; verification roles fall back to Codex. Note this degradation in the report.

## State File

Persisted to `<state-dir>/state.md` (survives compaction; outside the target repository):

```yaml
---
schema: contradiction-lift/v3   # v3: state file moved to <state-dir>; Codex actor keys are codex:<uuid> (records only, never continued); adds degraded / codex_call_failures / anonymization_key and the Anonymized Solutions section. v1 / v2 files are not migrated (start a new run).
task_id: 20260621-090000-12345
created: 2026-06-21T09:00:00Z
question: "Should the loop stop on fixed rounds or convergence detection?"
mode: codex
state: contract            # contract|sealed|mapped|adjudicated|preserved|lifted|accepted|aporia|no_material_divergence
degraded: false            # true once any role was degraded (claude-only, exit-2 fallback, user-approved subagent substitution)
codex_call_failures: []    # - {role: solver-b, exit: 4, attempt: 1}
solver_a_role: claude-subagent  # claude-subagent (default) | orchestrator-fallback (only when the Task tool is unavailable — sealing degrades to disciplinary)
solver_b_thread_id: ""     # "codex:<uuid>" for Solver B (claude-subagent-solverB in claude-only mode)
anonymization_key: ""      # e.g. "X=A,Y=B" — never pasted into any role prompt
mapper_role: ""            # claude-subagent | codex-thread (anonymized)
mapper_thread_id: ""       # actor key: codex:<uuid> | claude-subagent-mapper — raw value MUST differ from solver_b_thread_id
lift_role: ""              # claude-subagent | codex-thread (anonymized)
lift_thread_id: ""         # actor key: codex:<uuid> | claude-subagent-lift
audit_role: ""             # claude-subagent | codex-thread — prefer the OPPOSITE model to lift_role
audit_thread_id: ""        # actor key: codex:<uuid> | claude-subagent-audit — raw value (codex: stripped) MUST differ from lift_thread_id
empirical_arbiter: pending # pending|done|not_applicable|deferred (deferred = an empirical disagreement exists but the experiment can't be run this session)
lift_attempts: 0
max_lift_attempts: 2
outcome: pending           # pending|lifted|aporia|no_material_divergence
---

# Contradiction Lift: <question>

## Decision Contract
### Referenced files
## Sealed Solutions
### Solution A (Claude)
### Solution B (Codex)
## Anonymized Solutions
### Solution X
### Solution Y
## Divergence Ledger
## Adjudication
## Preservation
### X-steelmans-Y
### Y-steelmans-X
### Review of X-steelmans-Y
### Review of Y-steelmans-X
### Repairs
### Certification
## Lift
## Audit
```

`### Attempt <n>` headings under `## Lift` / `## Audit` are added only when that attempt's result is written — never pre-created empty.

## Safety Guards

- Every Codex role runs through `run-codex-role.sh`, which is always a fresh, read-only call (a result with changed files is rejected as exit 5). Only an experiment that must build/run needs writes — that is outside this skill's Codex path (user-run with confirmation, or `deferred`).
- **Sealing is structural**: Solver A is a fresh Claude subagent (not the orchestrator), dispatched in parallel with Solver B; the orchestrator reads neither until both return. Never pass Solution A into Solver B's prompt (or vice versa) before both are sealed — enforced by the `solver-b` allowlist (`Decision Contract` only).
- **The orchestrator never authors** a solution / steelman / lift / audit — each runs in a fresh role. **One documented exception:** when the Task tool is unavailable, **Solver A and its Phase 4 party actions** (the Claude-side steelman/review) fall back to the orchestrator (`solver_a_role: orchestrator-fallback`); sealing degrades to disciplinary and the Claude party action loses its fresh-context separation — flag both degradations in the report.
- **Subagents are analysis-only**: a Claude-subagent role must not write files — use a read-only subagent type where available and instruct the subagent to produce only the requested artifact (no edits, no commits). The state file is written by the orchestrator, not the role.
- **Anonymize** A/B → X/Y for Mapper / Lift Architect / Meta Auditor (and the Phase 4 party prompts), strip self-identifying wording, never paste `Sealed Solutions/*` or `anonymization_key`, and do not pass prior reasoning history. Check every `inputs.json` against the Non-leak allowlists before running.
- **Roles must be mutually distinct** where independence matters: Mapper ≠ Solver B, Lift Architect ≠ mapper/solver, and auditor ≠ architect (`audit_thread_id ≠ lift_thread_id`, compared with `codex:` stripped). Each independence-bearing role gets its **own** fresh subagent/call. The unequal comparison (`claude-subagent-lift ≠ claude-subagent-audit`) is a **procedural record that distinct roles were dispatched**, not a runtime proof — actual freshness is guaranteed by **always dispatching a new subagent / Codex call for each role** (never reusing one). For the audit, prefer the **opposite model** to the Lift Architect.
- Confirm before any file modification (this skill is analytical; writes are limited to `<state-dir>` and the final report).

## Error Handling

- **Codex unavailable (exit 2) in codex mode:** degrade to `claude-only` per 実行モード; **warn** that independence is weak (two passes by the same model) and name every role that lost cross-model pairing. No Task tool either → stop.
- **A Codex role fails with exit 4 / 5:** **no automatic retry**, no automatic degradation — show `error.log` and ask the user (new attempt / fresh Claude subagent for that role with an explicit same-prior caveat / stop). If the Task tool is unavailable too, **stop**, leave `state` at its last valid value (do not invent a new state), and report the **run** as incomplete.
- **Exit 1:** caller error (bad arguments or reused attempt directory) — fix and use a new attempt directory.
- **Lift keeps failing audit:** after `max_lift_attempts`, declare an **honest aporia** (do not manufacture a synthesis — that disguises an average).
- **Early stop requested:** report the current `state` (sealed solutions / ledger / lift so far) and note no lift was reached.

## Output Format

Three possible outcomes, all first-class:

**Accepted lift:**
```
Contradiction Lift — ACCEPTED
Question:  <Q>
Lift:      <selection mechanism — f(C) → A | B | N>
Conserves: A: <...> | B: <...>
New:       <variable/relation absent from both originals>
Selects A when: <example>   Selects B when: <example>
Differs from average when: <example>
Fails if:  <falsification condition>
Audit:     7/7 passed, causal check = yes
Log: <state-dir>/state.md
```

**Honest aporia:**
```
Contradiction Lift — APORIA (not lifted)
Question:  <Q>
Irreducible axis: <the trade-off that cannot be sublated>
A is right when: <condition C1>   B is right when: <condition C2>
Why no lift: <which audit test failed twice, and why>
Log: <state-dir>/state.md
```

**No material divergence:**
```
Contradiction Lift — NO MATERIAL DIVERGENCE
Question:  <Q>
Shared load-bearing core: <what both A and B agree on>
Minor/dissolvable differences: <semantic/style only — not lifted>
Note: nothing to lift; a contradiction was not manufactured.
Log: <state-dir>/state.md
```

## Invoking the Skill

```bash
# Lift two independent solutions to an execution-undecidable question
/agent-dialectics:contradiction-lift "Should dialectic-loop stop on fixed rounds or convergence detection?"

# Claude-only (degraded — independence is weak; codex recommended)
/agent-dialectics:contradiction-lift --mode claude-only "Composition vs inheritance for this module hierarchy"

# Cap lift retries
/agent-dialectics:contradiction-lift --max-lift-attempts 1 "Monorepo vs polyrepo for this org"
```

## Compact Recovery

1. `TaskList` for progress; recompute `<state-dir>` and read `<state-dir>/state.md`; read `state` / `*_thread_id` / `lift_attempts` / `degraded` / `codex_call_failures`.
2. Resume by `state`:

| State | Resume at |
|-------|-----------|
| `contract` | Phase 0 (or Phase 1 if contract present) |
| `sealed` | Phase 2 (Divergence Mapping) |
| `mapped` | Phase 3 (Adjudication Router) |
| `adjudicated` | Phase 4 (Preservation) |
| `preserved` | Phase 5 (Lift Construction) |
| `lifted` | Phase 6 (Audit) |
| `accepted` / `aporia` / `no_material_divergence` | Report |

3. **Attempt directories**: before re-dispatching any Codex role, look for its `<role>-<attempt>` / `<role>-r<n>-<attempt>` directory and follow the 再開規則 in Codex 役の呼び出し (`DONE` → reuse `answer.md`; live pid → wait; dead pid without `DONE` → ask the user; `failed` → exit 4/5 rules).
4. **Role recovery**: every independence-bearing role is **stateless and re-startable from disk** — Codex roles are fresh calls rebuilt from the same allowlisted `state.md` sections, and Claude-subagent roles (incl. Solver A's Phase-4 party actions) are re-dispatched as fresh subagents re-seeded from the same sections. Nothing is ever continued. Keep raw `audit_thread_id ≠ lift_thread_id` on restart.
5. **Old state files are not migrated**: a `v1` / `v2` file (the old in-repository `tmp/` location) is not resumed. Tell the user it was found and start a new run with a new task id under `<state-dir>`; the old file may be read by the user for reference only.
6. **Lift attempt numbering on resume**: in state `preserved` (or after a failed audit), recompute `n` as in Step 7 — `### Attempt` entries under `## Audit` with a recorded 7-test result + 1 — and resume an existing `lift-r<n>-<attempt>` directory by the 再開規則 rather than starting `lift-r<n+1>`.

## Notes

- **Sealing is structural**: Solver A is a fresh Claude subagent (not the orchestrator), dispatched in parallel with Solver B; the orchestrator authors neither and reads neither until both return.
- **Two kinds of independence** (see "Independence: two kinds"): keep **solvers cross-model** (Claude subagent × Codex), and **pair verification across models**. A same-model agreement is not confirmation.
- **Never optimize for agreement / average / residual-shrink.** A diluted middle ground is failure; an honest aporia beats a fake third term.
- Inside bash blocks in this file, do not use positional-parameter notation (`$` followed by a digit) — this file is argument-substituted.

## References

Detailed templates in `references/`:

- **`sealed-solution-template.md`** — the schema each solver fills in Phase 1 (decision function, load-bearing assumptions, flip observation).
- **`divergence-map-template.md`** — the anonymized disagreement ledger (typed divergence + flip-test) for Phase 2.
- **`lift-audit-template.md`** — the Lift Construction output format and the Phase 6 seven-test audit + aporia criteria.
