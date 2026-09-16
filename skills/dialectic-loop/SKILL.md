---
name: dialectic-loop
description: 'This skill should be used when the user wants to "test a claim against data", "validate an empirical hypothesis", "refine a model/theory with evidence", "characterize a pattern and verify it", "演繹と帰納で検証", "仮説をデータで検証して更新", "実例と反例で確かめる", "弁証法ループ", "主張を現物で裏取り", "傾向分析を検証して精緻化", or mentions iteratively updating a hypothesis by deriving predictions and testing them against a real corpus. NOTE: Use this for VALIDATING/REFINING an empirical claim or model against real data through a derive→test→update loop. Use strong-inference for debugging an UNKNOWN cause, and devils-advocate for adversarially stress-testing a DESIGN proposal.'
argument-hint: '[claim] [--corpus PATH/GLOB] [--mode codex|claude-only] [--max-rounds N] [--rotate] [--abduce]'
---

# Dialectic Loop Skill

Validate and refine an empirical claim or model by running C.S. Peirce's inquiry cycle — **abduction → deduction → induction** — across three roles that debate and update a hypothesis against real data.

## Claim

$ARGUMENTS

## Overview

A Dialectic Loop improves the quality of a *claim about reality* (a trend, a pattern, a characterization, an empirical model) by:

1. **Deriving** falsifiable predictions from a hypothesis (deductive role)
2. **Testing** those predictions against a real corpus — surfacing supporting instances **and actively hunting counterexamples** (inductive role)
3. **Arbitrating** the gap between prediction and evidence, then **updating** the hypothesis (arbiter role)
4. **Iterating** until the hypothesis stabilizes (converges)

The output is not approve/reject and not a root cause — it is a **refined hypothesis (H′) with an evidence-backed confidence level and a record of what the original framing got wrong.**

**Key feature**: In codex mode, the **inductive role is assigned to Codex** so the empirical test is performed by a *different model than the one that authored the hypothesis*. This independence is the point — it is what catches the hypothesis author's confirmation bias.

## 利用量ポリシーとロール表

1. **Codex 役は常に fresh**。反復（ラウンド、再レビュー）は「前回までの要約（確定事項・未解決・却下案）+ 必要な抜粋」を含む自己完結プロンプトで再投入する。thread を継続しない
2. **事実はプロンプトに持たせる**。Claude 側で読んだファイル抜粋・行番号・確認済み事実を prompt.md に入れる。「リポジトリを探索して検証せよ」とは指示しない。ディスク読取を許すのは、下表で「読取が役割」と宣言したロールだけ
3. **Web 検索は使わない**よう、全ロールの prompt に明記する
4. **入力トークン上限**: 1 呼び出しあたり 10 万トークン。超えたらプロンプトを見直す（例外は下表で個別上限を宣言したロールのみ）

| ロール | 担当 | `--model` / `--effort` | ディスク読取 | 入力上限 |
|---|---|---|---|---|
| `abduction`（`--abduce` の Phase 0a のみ） | Codex | 既定（config.toml） | 可（corpus のみ） | 30 万（corpus 計測のため個別宣言） |
| `induction-r<N>`（各ラウンドの Phase 3。`--rotate` で Claude 担当になったラウンドを除く） | Codex | 既定（config.toml） | 可（corpus のみ） | 30 万（corpus 計測のため個別宣言） |
| `deduction-r<N>`（`--rotate` で Codex 担当になったラウンドの Phase 2 のみ） | Codex | 既定（config.toml） | 不可 | 10 万 |
| Hypothesis selection（Phase 0b）/ deduction（既定）/ arbitration | Claude | — | —（arbiter は disk recompute のため corpus を読む） | — |

ユーザーは実行時にこの表の model / effort を上書きできる（例: 「induction は既定モデルで」）。

Role ids are the `<role>` used in the attempt directory, the prompt marker, and `inputs.json`:

- `abduction` → attempt dir `abduction-<attempt>`, marker `<!-- agent-dialectics-role: dialectic-loop/abduction -->`
- `induction-r<N>` → attempt dir `induction-r<N>-<attempt>`, marker `<!-- agent-dialectics-role: dialectic-loop/induction-r<N> -->`
- `deduction-r<N>` → attempt dir `deduction-r<N>-<attempt>`, marker `<!-- agent-dialectics-role: dialectic-loop/deduction-r<N> -->`

**abduction and induction are always separate roles and separate fresh calls.** Their `threadId`s (from each attempt's `meta.json`) are recorded as `abduction_thread_id: codex:<uuid>` and `induction_thread_id: codex:<uuid>` and **must differ**. If they are ever equal, treat it like exit 5 (invalid result): do not advance the phase; show both attempt directories to the user and ask how to proceed.

## Comparison with sibling skills

| Aspect | Strong Inference | Devil's Advocate | **Dialectic Loop** |
|--------|------------------|------------------|--------------------|
| Purpose | Find an unknown cause | Stress-test a design proposal | **Validate/refine an empirical claim or model** |
| Method | Competing hypotheses + eliminating experiments | Blue vs Red adversarial debate | **Derive predictions → test on real data → update** |
| Engine of truth | Decisive experiment | Adversarial critique | **Counterexample hunting on a real corpus** |
| Output | Root cause + evidence trail | Verdict (APPROVE/CONDITIONAL/REJECT) | **Refined hypothesis H′ + confidence + "what was missed"** |
| Loop ends when | One hypothesis survives | Max rounds / verdict | **Hypothesis converges (stops changing)** |
| Best for | Debugging | Design review | Trend analysis, profiling, theory refinement, claim-checking |

## Prerequisites

- The user has a **claim, hypothesis, or model** to validate (e.g. "X tends to do Y", "this pattern holds", "the system behaves like Z").
- A **corpus / data source** that can ground the test exists and is accessible (codebase, logs, dataset, documents).
- For codex mode: the official codex-plugin-cc (`codex@openai-codex`) is installed and Codex CLI is logged in. Availability is detected by `run-codex-role.sh` (exit code 2), not checked in advance.

## Design principles (lessons baked in)

These are non-negotiable; they are what make the loop work rather than perform theater:

1. **Ground the inductive role in current artifacts.** The inductive verifier MUST re-read data from disk (ignore cached content), and MUST process large data with scripts/grep rather than eyeballing. A prediction "tested" without touching the corpus is invalid.
2. **Name roles by function, not persona.** The inductive role's job is *measurement + counterexample hunting*, not "acting inductive." The deductive role's job is *deriving falsifiable consequences*, not "being logical."
3. **The arbiter is mandatory.** Without a third role, a partially-falsified prediction gets quietly recorded as "partial support." The arbiter exists to force the question: *where did the hypothesis over- or under-reach?*
4. **Independence beats agreement.** Assign the inductive test to a different model than the hypothesis author. A confirming result from the same author is weak; a counterexample from an independent verifier is strong.
5. **Converge, don't exhaust.** Stop when H′ stops changing materially, not at a fixed round count.
6. **In the `--abduce` variant, preserve independence structurally (Codex authors *and* tests).** Four guards make this honest: (a) **Predictions are Claude's** — the believer does not design the test. (b) **Arbitration is Claude's, with a mandatory disk recompute** — the believer does not grade the result; the arbiter re-measures from disk (full, or sampled with recorded method/tolerance). (c) **Call isolation** — every induction call is a *fresh* call whose prompt is built only from the allowed state sections (see **Non-leak rule**), never from the `## Abduction` section (no context contamination). (d) **In-sample honesty** — if H is abduced from the same corpus it is tested on, that is discovery=validation fit; mark `evidence_scope: exploratory_in_sample` and recommend a holdout/fresh corpus for confirmatory strength.

## Codex 役の呼び出し

<!-- shared:codex-role-protocol start (4手法で同一。変更時は 4 ファイルすべてに反映する。scripts/lint-plugin.sh の Check 7 が一致を検査) -->

Codex が担当するロールは、プラグイン同梱の `scripts/run-codex-role.sh`（公式 codex-plugin-cc companion の `task --fresh --json` を read-only で 1 回呼ぶラッパー）だけで呼ぶ。`/codex:rescue` や `codex exec` を直接使わない。

**スクリプトの場所**: このスキルの読み込み時に表示される base directory（`.../skills/dialectic-loop`）から `<base>/../../scripts/run-codex-role.sh` を組み立てる。`${CLAUDE_PLUGIN_ROOT}` が展開されていればそちらを優先する。

**作業ディレクトリ（対象リポジトリの外）**:

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
echo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG/dialectic-loop/<task-id>"
```

- `<state-dir>/state.md` — 手法の状態ファイル（相・終端状態・中断再開用）。frontmatter の `created` は `date -u +%Y-%m-%dT%H:%M:%SZ` の出力をそのまま書く（ローカル時刻に `Z` を付けない）
- `<state-dir>/<role>-<attempt>/` — Codex 呼び出し 1 回分（`attempt` は 1 から）。反復ロールは `<role>-r<round>-<attempt>`
  - `prompt.md` — 送るプロンプト。**1 行目は必ず** `<!-- agent-dialectics-role: dialectic-loop/<role> -->`（反復ロールは `<role>-r<round>`）
  - `inputs.json` — prompt.md と同時に Write で書く: `{"method": "dialectic-loop", "role": "<role>", "state_sections": ["<state.md の節名>", ...], "artifacts": ["<絶対パス>", ...]}`（prompt 組み立てに使った状態ファイル節と成果物の一覧。非漏洩検査に使う）
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

**Prompt preamble (every Codex role)**: after the marker line, every `prompt.md` states (1) answer in the language of the current conversation, (2) do not use web search, (3) this is read-only analysis — do not modify any file. The corpus paths in the prompt are absolute (the corpus may live outside `<ROOT>`).

## 実行モード

- `codex`（既定）: Codex 役を `run-codex-role.sh` で呼ぶ
- `claude-only`: `--mode claude-only` の明示指定時、または `run-codex-role.sh` が **終了コード 2** を返したときに、**ユーザーに明示的に警告したうえで**縮退する
- **縮退時の警告は、縮退した時点で出す（必須、default variant）**: 終了コード 2 を受け取ったら、**次のツール呼び出し（Claude サブエージェントの起動、状態ファイルの更新を含む）より前に**、ユーザー向けのテキストとして次の警告を出す。最終レポートの注記や「Claude のサブエージェントに書かせています」のような途中経過の説明では代わりにならない。理由は完了通知など取得済みの情報から書き、未取得なら「詳細未確認」とする（理由を調べるためのツール呼び出しは警告のあとで行い、必要なら補足する）

  > ⚠️ Codex を使えないため（`run-codex-role.sh` 終了コード 2: `<error.log の理由を 1 行>`）、`<role>` 以降を Claude だけで続けます（`degraded: true`）。別モデルによる独立した確認がないため、結論の確かさは下がります。
- 状態ファイルに `degraded: true|false` と `codex_call_failures`（`- {role, exit, attempt}` のリスト）を分けて記録する
- 終了コード 4 / 5 は縮退理由にしない（自動再実行も自動縮退もしない。ユーザー判断）
- 同一モデル（Claude が Claude の結論を確認）の一致を独立した裏付けに数えない
- **`--abduce`（abduction variant）は縮退禁止**: `abduction` / `induction-r<N>` のどちらでも終了コード 2 が返ったら claude-only に縮退せず、`status: blocked_no_codex` を記録して停止する（Claude が仮説を生成・検証すると author≠verifier の契約が崩れるため）。その後の選択肢は **Error Handling → `--abduce` failure** に従う
- **`--abduce --mode claude-only` はエラー**（開始しない）
- claude-only で Claude が帰納役を担う場合も、corpus をディスクから読み直してスクリプトで計測し、反例を探す義務は変わらない。confidence は「独立検証なし」として控えめにする

## Workflow

### Step 1: Parse Arguments and Initialize

1. **Parse options** from the Claim (`$ARGUMENTS`): `--corpus <path|glob>`, `--mode <codex|claude-only>`, `--max-rounds <N>`, `--rotate`, `--abduce`. The remainder is the claim.
2. **Determine mode**: default `codex`; honor `--mode` override. Do not probe for Codex in advance — availability is learned from the first `run-codex-role.sh` call (exit 2). Default `--max-rounds` is 3.
3. **`--abduce` (abduction variant) validation** — when `--abduce` is present:
   - It is the **only** trigger for the abduction variant; omitting the claim alone does **not** auto-enable it.
   - **`--corpus` is required** (Codex needs a corpus to abduce from). The claim is **optional** (Codex generates it).
   - **Requires `mode = codex`.** `--abduce --mode claude-only` is an **error** (abduction is delegated to Codex) — stop and tell the user.
   - **`--abduce --rotate` is an error** (the abduction variant fixes roles: Codex = abduction + induction, Claude = deduction + arbitration; rotation has no defined meaning) — stop and tell the user.
   - Set `variant: codex-abduction` (default otherwise is `variant: default`).
4. **Confirm the corpus** with the user if `--corpus` was omitted (default variant). If the corpus is inaccessible, stop and ask for a valid path rather than guessing.
5. **Generate the task id** (`YYYYMMDD-HHMMSS-<random>`, e.g. `TASK_ID="$(date +%Y%m%d-%H%M%S)-$RANDOM"`, the same format as the other method skills), compute `<state-dir>` with the snippet in **Codex 役の呼び出し**, create it (`mkdir -p`), and write `<state-dir>/state.md` with the Write tool using the `dialectic-loop/v3` schema (see **State File**). Do not use shell text substitution to embed the claim/corpus.
6. **Routing**: if `variant = codex-abduction` → **Step 1.5 (Phase 0)**. Otherwise → **Step 2 (Phase 1)**.

### Step 1.5: Phase 0 — Abduction (Codex) — `--abduce` only

Skipped in the default variant (the user/Claude supplies the hypothesis). When `--abduce` is set, Codex generates the hypothesis from the corpus in two sub-stages. The abduction call is **separate** from every later induction call.

**0a. Candidate generation (Codex, role `abduction`).**

1. Write `<state-dir>/abduction-<attempt>/prompt.md`: `references/abduction-template.md` (which already starts with the marker line and the prompt preamble) filled with the corpus paths/extraction rule and the optional seed claim.
2. Write `inputs.json` at the same time: `{"method": "dialectic-loop", "role": "abduction", "state_sections": ["frontmatter.corpus", "frontmatter.original_claim"], "artifacts": []}`.
3. Run `run-codex-role.sh` (no `--model` / `--effort`) in the background and wait.
- Demand **multiple competing candidate hypotheses** (not one), each with the observations that suggest it, an alternative explanation, and a discriminating measure hint.
- **Persist the candidates first**: write Codex's full candidate list (from `answer.md`) into a `## Abduction` → `### Candidates` section of the state file, record **`abduction_thread_id: codex:<uuid>`** from `meta.json`, and **only then** set `abduction_status: done`. (Compact Recovery's "candidates present" check depends on this — do not mark done before the candidates are on disk.)
- On exit ≠ 0, follow **Error Handling → `--abduce` failure** (exit 2 → `status: blocked_no_codex`; never degrade to claude-only; exit 4/5 never retried automatically).

**0b. Hypothesis selection (Claude / user).** Claude evaluates the candidates (falsifiability, discriminability, how much it would teach if wrong) and selects one — or presents them with `AskUserQuestion` for the user to choose / edit. Record the selection rationale under `## Abduction` → `### Selection`, the chosen hypothesis as `confirmed_hypothesis` (and mirror it into `claim`), set `hypothesis_status: confirmed`, and `original_claim` (the user-supplied claim if any, else empty). This confirmed hypothesis becomes **H** for Phase 1+.

After 0b, continue to **Step 2** with H = `confirmed_hypothesis`.

### Step 2: Phase 1 — Claim Definition

- Restate the hypothesis in one falsifiable sentence (in the abduction variant, this is `confirmed_hypothesis`). Write it **origin-neutrally** (no mention of who authored it or of candidates).
- Pin the grounding corpus and extraction rule (absolute paths, how to isolate the relevant records).
- Clarify scope and what would count as the claim being **false**.
- Write `## Claim Definition` with `### Corpus and extraction rule` and `### Falsity criterion`, then `## Round 1` with `### Hypothesis (H)`; set `phase: deductive`.

### Step 3: Phase 2 — Deductive Derivation (Claude by default)

Take the hypothesis **as given** and, following `references/prediction-template.md`, derive **3–5 falsifiable predictions**, each with 支持条件 / 反証条件 / Measure, including **at least one counter-test**. A prediction with no falsifier is rejected and rewritten. Append them under `## Round <N>` → `### Deductive — Predictions` with the Edit tool.

**`--rotate` rounds where deduction is Codex's (role `deduction-r<N>`)**: write `deduction-r<N>-<attempt>/prompt.md` = marker + preamble + the rules and per-prediction structure of `references/prediction-template.md` + the current H + the corpus rule + the prior rounds' scorecards. `inputs.json` `state_sections`: `["Claim Definition / Corpus and extraction rule", "Round <N> / Hypothesis (H)", "Round <k> / Arbitration / Scorecard" for every k < N]`. The prompt says not to read the corpus (derivation only). Claude checks every prediction has a falsifier and at least one counter-test before recording.

### Step 4: Phase 3 — Inductive Verification

Set `phase: inductive`.

**If mode = codex (and induction is Codex's this round)** — role `induction-r<N>`, always a **fresh** call (Round 1 and every later round alike):

1. Write `<state-dir>/induction-r<N>-<attempt>/prompt.md`: `references/induction-verification-template.md` (which already starts with marker `<!-- agent-dialectics-role: dialectic-loop/induction-r<N> -->` and the prompt preamble) filled from these state sections only:
   - `Claim Definition / Corpus and extraction rule`
   - `Round <N> / Hypothesis (H)`
   - `Round <N> / Deductive — Predictions`
   - Round 2+: for every k < N, `Round <k> / Inductive — Evidence`, `Round <k> / Arbitration / Scorecard`, `Round <k> / Arbitration / Disk recompute` (prior verdicts and measurements, pasted verbatim into the template's "Prior rounds" section; Round 1 leaves it empty)
2. Write `inputs.json` with exactly those names in `state_sections` (and `"artifacts": []`).
3. Run `run-codex-role.sh` (no `--model` / `--effort`) in the background and wait.
4. On exit 0: record the `threadId` as **`induction_thread_id: codex:<uuid>`** (frontmatter holds the latest round; also write `- thread: codex:<uuid> (attempt: induction-r<N>-<attempt>)` at the top of the round's evidence section). In the abduction variant, check `induction_thread_id ≠ abduction_thread_id` (see the role table rule).

**Non-leak rule (load-bearing, especially with `--abduce`)**: the `state_sections` of any `induction-r<N>` call **must not** contain `Abduction`, `Abduction / Candidates`, `Abduction / Selection`, or `frontmatter.original_claim`, and the prompt must not quote them. Never pass the abduction candidates, rationale, or confidence to induction, and never state who authored H — in the abduction variant use the origin-neutral opening described in the template. The inductive verifier tests H on its merits, blind to its origin. The same restriction applies to `deduction-r<N>`.

**Exit handling**: follow the exit-code table. In the **default variant**, exit 2 degrades to claude-only with an explicit warning (`degraded: true`, append to `codex_call_failures`); exit 4/5 → show `error.log`, do not advance, and ask the user (retry with a new attempt / stop / explicitly switch the remaining rounds to claude-only, recorded as `degraded: true`). In the **`--abduce` variant**, follow Error Handling → `--abduce` failure.

**If mode = claude-only (or induction is Claude's this `--rotate` round)** — Claude performs the empirical pass itself, but MUST script over the real corpus (re-read from disk, no cached content) and actively hunt counterexamples. If delegated to a Claude subagent, record `induction_thread_id: claude-subagent-induction-r<N>`.

Append the verdicts under `## Round <N>` → `### Inductive — Evidence` (per-prediction 【支持/部分支持/反証】 + numbers + quotes + 総合所見).

### Step 5: Phase 4 — Arbitration (Claude)

Write `## Round <N>` → `### Arbitration` with three subsections:

- `#### Scorecard` — each Pi: predicted vs observed → 支持/部分支持/反証. Explicitly name every prediction where the deductive framing **over- or under-reached** (partial/falsified ones). Fold in the inductive role's missed-nuances.
- `#### Disk recompute` — **Second independent verification (mandatory in the `--abduce` variant; recommended always):** Claude **re-reads the corpus from disk** and **recomputes each Measure** that drives a verdict — by default **in full**. If full recomputation is infeasible, sample and record: the sampling method, the count, the selection/seed rule, the tolerance, and the mismatch criterion (a rate verified only by a few cherry-picked examples does **not** count). Record any Codex-vs-disk discrepancy and fold it into the confidence.
- `#### H′ and confidence` — **H′** (updated hypothesis, rephrased to survive the evidence), **confidence** (low/medium/high) with reasoning (robustness, independence of evidence), and `evidence_scope`.
  - **Evidence scope (abduction variant):** when the hypothesis was **abduced from the same corpus** it is now tested on, this is in-sample fit (discovery = validation data). Set `evidence_scope: exploratory_in_sample`, keep `confidence` modest, and note that **confirmatory strength requires a holdout / fresh corpus**. When discovery and validation corpora differ, use `evidence_scope: confirmatory`.

Do not mention abduction candidates in the `Scorecard` or `Disk recompute` subsections (they are fed to later induction calls). Set `phase: arbitration` and increment `round`.

### Step 6: Phase 5 — Iterate or Conclude

- If **H′ changed materially** and `round < max_rounds` → write `## Round <N+1>` → `### Hypothesis (H)` = H′ and return to **Step 3** (apply `--rotate` if set: swap deductive/inductive authorship for that round).
- If **H′ converged** (≈ previous H), `round >= max_rounds`, or the user requests stop → proceed to Step 7.

### Step 7: Phase 6 — Conclude and Report

Set `phase: report`, `status: completed`, and final `confidence` (and `evidence_scope`) in the state file, then report to the user:

```markdown
## Dialectic Loop Complete

**Claim (H):**    <original — for --abduce, note "abduced by Codex" + original_claim if any>
**Refined (H′):** <hypothesis that survived the evidence>
**Confidence:**   <low/medium/high> (<why — independence, N, falsified predictions>)
**Evidence:**     <confirmatory | exploratory_in_sample> (<for in-sample: recommend holdout/fresh corpus to confirm>)
**Mode:**         <codex | claude-only> (degraded: <true|false>)

### Prediction scorecard
- P1 <verdict> (<measure>) · P2 ... · P3 ... · P4 ...

### What the original framing missed
1. ...
2. ...

Loop log: <state-dir>/state.md
```

## Role Distribution

| Variant / Mode | Hypothesis (abduction) | Predictions (deductive) | Empirical Test (inductive) | Arbitration |
|------|------|------|------|------|
| default · `codex` | user / Claude | Claude | **Codex** (independent, read-only, grounded, fresh call per round) | Claude |
| default · `claude-only` | user / Claude | Claude | Claude (must still script over real corpus) | Claude |
| **`--abduce`** (codex only) | **Codex** (from corpus, role `abduction`) | Claude | **Codex** (role `induction-r<N>`, separate fresh call) | Claude (+ mandatory disk recompute) |

- **Default mode**: `codex` (independence is the design goal; degrade to claude-only with an explicit warning only on exit 2).
- **Optional**: `--rotate` swaps deductive/inductive authorship between rounds to further reduce single-model bias (Codex takes `deduction-r<N>`, Claude takes induction in that round).
- **`--abduce` (abduction variant)**: Codex *generates* the hypothesis from the corpus (abduction), Claude derives predictions and arbitrates. This removes the default variant's weakness — that Claude grades its own hypothesis — by making author (Codex) ≠ arbiter (Claude). Requires `mode = codex`; incompatible with `--mode claude-only` and `--rotate` (both error); never degrades. See **Design principles #6** for the independence guards that keep "Codex authors *and* tests" honest.

## State File

Loop state is persisted to `<state-dir>/state.md` (see **Codex 役の呼び出し** for `<state-dir>`).

Schema `dialectic-loop/v3` is used for both variants. v3 supersedes v1 (default) and v2 (abduction): it moves the file to the state dir, records thread ids as `codex:<uuid>` (for the record only — never used to continue a thread), makes induction a fresh call per round, and adds `degraded` / `codex_call_failures`. Methodology fields are unchanged; abduction fields stay empty in the default variant. Older state files are not migrated — start a new loop.

```yaml
---
schema: dialectic-loop/v3
task_id: 20260620-090000
created: 2026-06-20T09:00:00Z
variant: default                  # default | codex-abduction
roles: "deduction=Claude, induction=Codex, arbitration=Claude"   # abduction variant: "abduction=Codex, deduction=Claude, induction=Codex, arbitration=Claude"
phase: deductive                  # (abduction →) deductive → inductive → arbitration → report
claim: "masuP9 holds judgments provisionally but cuts actions decisively"   # abduction variant: mirrors confirmed_hypothesis once Phase 0b selects it (empty before)
corpus: "/home/masup9/.claude/projects/**/*.jsonl (user utterances)"
mode: codex                       # codex | claude-only
round: 1
max_rounds: 3
rotate: false
status: in_progress               # in_progress | completed | blocked_no_codex | aborted
confidence: pending               # → low | medium | high (Phase 4)
evidence_scope: pending           # → confirmatory | exploratory_in_sample (Phase 4)
degraded: false
codex_call_failures: []           # - {role: induction-r1, exit: 4, attempt: 1}
# abduction variant fields (empty / pending in the default variant)
original_claim: ""                # user-supplied claim if any (else empty — Codex abduces)
confirmed_hypothesis: ""          # set in Phase 0b (selection)
abduction_status: pending         # pending → done (set AFTER candidates persisted)
hypothesis_status: pending        # pending → confirmed (after Phase 0b)
abduction_thread_id: ""           # "codex:<uuid>", set in Phase 0a
induction_thread_id: ""           # "codex:<uuid>" of the latest induction-r<N> call — MUST differ from abduction_thread_id
---

# Dialectic Loop: <claim>

## Abduction                      <!-- abduction variant only; NEVER fed to induction-r<N> / deduction-r<N> -->
### Candidates
### Selection

## Claim Definition
### Corpus and extraction rule
### Falsity criterion

## Round 1

### Hypothesis (H)
...

### Deductive — Predictions
- P1: ... | 支持条件: ... | 反証条件: ...
- P2: ... (counter-test) | ...

### Inductive — Evidence (Codex)
- thread: codex:<uuid> (attempt: induction-r1-1)
- P1: 【支持】rate=72% — "quote", "quote"
- P2: 【部分支持】27.7% — "quote"
- 総合所見: ...（演繹役が見落とした反例: ...）

### Arbitration
#### Scorecard
- P1 支持 / P2 部分支持（演繹役が過大評価）/ ...
#### Disk recompute
- full recompute: P1 72% (Codex) vs 71.8% (disk) — within tolerance
#### H′ and confidence
- H′: ...
- Confidence: medium — independent extraction, N=423

## Round 2
...
```

State section names used in `inputs.json` are the heading path joined with ` / ` (e.g. `Round 2 / Arbitration / Scorecard`); frontmatter fields are `frontmatter.<field>`.

## Error Handling

- **Codex unavailable (exit 2) in codex mode, default variant:** degrade to claude-only with an explicit warning to the user; set `degraded: true` and append to `codex_call_failures`.
- **Exit 4 / 5 (any variant):** never retried automatically and never a reason to degrade. Show `error.log`, keep the phase, record the failure, ask the user.
- **`--abduce` failure (exit 2 / 4 / 5 on `abduction` or `induction-r<N>`):** do **NOT** fall back to claude-only — having Claude generate or test the hypothesis breaks the author≠verifier contract. On exit 2 set `status: blocked_no_codex`. Stop, record the failure, then ask the user whether to (a) retry (new attempt directory), (b) abort (`status: aborted`), or (c) switch to the **default variant** with an explicit user-supplied claim (claim then required; that variant may itself degrade under the 実行モード rules).
- **`abduction_thread_id` equals `induction_thread_id`:** treat as an invalid result (like exit 5); do not advance; ask the user.
- **Inductive role returns no numbers:** treat the prediction as unverified; ask the user before re-running (new attempt) with an explicit demand to compute the Measure over the corpus.
- **Corpus inaccessible:** stop and ask the user for a valid path rather than guessing.
- **Early stop requested:** report H′ so far with interim confidence and note the loop did not converge.

## Safety Guards

- Codex roles run **read-only** via `run-codex-role.sh`; any touched file makes the call exit 5.
- The inductive role must **re-read from disk** and **script over large corpora** (no raw-dump reading, no cached content).
- Confirm before any file modification (this skill is analytical; writes are limited to the state dir and the final report). Nothing is written into the target repository.
- **Abduction variant only:** the arbiter's disk recompute is **mandatory** (not optional); induction calls are **distinct** from the abduction call and obey the Non-leak rule; and on Codex failure, never fall back to claude-only.

## Output Format

### Progress Display

```
Dialectic Loop — Round 2 / 3
Claim: masuP9 holds judgments provisionally but cuts actions decisively

Predictions:
  [✓] P1 hedged judgments dominant      → 支持   (72%)
  [~] P2 judgment coupled to verify     → 部分支持 (28%)  ← deductive over-reach
  [✓] P3 no principle-only commands     → 支持   (0 found)
  [✓] P4 decision deferral present      → 支持   (8)

H′: provisional in belief, decisive in action; verifies selectively, not reflexively
Confidence: medium  |  Convergence: pending (H changed this round)
```

### Completion Report

See the template in **Step 7**.

## Invoking the Skill

```bash
# Basic — validate a claim against a corpus
/agent-dialectics:dialectic-loop "User X holds judgments provisionally but cuts actions decisively" --corpus "~/.claude/projects/**/*.jsonl"

# Mode + rounds
/agent-dialectics:dialectic-loop --mode claude-only --max-rounds 2 "This API degrades under concurrency"

# Rotate authorship to reduce bias
/agent-dialectics:dialectic-loop --rotate "Codebase favors composition over inheritance"

# Abduction variant — let Codex generate the hypothesis from the corpus (claim optional)
/agent-dialectics:dialectic-loop --abduce --corpus "scripts/**/*.sh"

# Japanese
/agent-dialectics:dialectic-loop 「この傾向分析の仮説をログで検証して精緻化して」
```

## Compact Recovery

If compacted mid-loop:

1. Run `TaskList` to see progress.
2. Recompute `<state-dir>` and read `<state-dir>/state.md`: `status`, `phase`, `round`, `*_status`, `*_thread_id`, and which sections are filled.
3. If an attempt directory for the current role exists (`abduction-<a>`, `induction-r<N>-<a>`, `deduction-r<N>-<a>`), apply the **再開規則** in **Codex 役の呼び出し** before anything else (reuse `DONE`, wait on a live pid, ask on `unknown` / `failed`).
4. Resume by state:

| State | Resume at |
|-------|-----------|
| `status: blocked_no_codex` | Ask the user: retry / abort / switch to default variant (Error Handling) |
| `variant: codex-abduction`, no candidates / `abduction_status` ≠ done | Phase 0a (apply 再開規則; a new attempt only with user approval) |
| candidates present, `hypothesis_status` ≠ confirmed | Phase 0b (selection) |
| H confirmed, no predictions | Phase 2 (deductive) |
| predictions present, no evidence | Phase 3 (inductive) |
| evidence present, no arbitration | Phase 4 (arbitration) |
| arbitration present, H′ changed, rounds remain | Phase 2 (next round) |
| H′ converged or max_rounds reached | Phase 6 (report) |

If candidates are already recorded, never re-run abduction. If an induction round has no successful attempt, rebuild its prompt from the allowed state sections (Non-leak rule) in a new attempt directory — with user approval — and recompute that round.

## Notes

- Loop state is persisted to survive compaction; each loop has a unique task id.
- The **inductive role must be grounded in the real corpus** (scripted, disk-read) — this is the skill's load-bearing constraint.
- The **arbiter is mandatory**: it exists to stop partial falsification from being glossed as partial support.
- Independence (inductive verifier ≠ hypothesis author) is the default and the point. In the **abduction variant** Codex authors *and* tests, so independence is preserved structurally instead: predictions are Claude's, arbitration is Claude's (with mandatory disk recompute), and every induction call is a fresh call isolated from the abduction call by the Non-leak rule.

## References

Detailed templates in `references/`:

- **`abduction-template.md`** — the prompt handed to Codex (role `abduction`) in the `--abduce` variant's Phase 0a to generate competing candidate hypotheses from the corpus.
- **`prediction-template.md`** — structure for the deductive role's falsifiable predictions.
- **`induction-verification-template.md`** — the prompt handed to the inductive role (Codex, role `induction-r<N>`), including the counterexample-hunting mandate.
