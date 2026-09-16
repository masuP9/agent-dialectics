# Induction Verification Template (Inductive Role → Codex)

This prompt is handed to the inductive role (Codex in `codex` mode, role `induction-r<N>`) in Phase 3.
Its purpose is an **independent empirical test** of the deductive role's predictions, with active counterexample hunting. Fill the `{{...}}` placeholders and write the result to `<state-dir>/induction-r<N>-<attempt>/prompt.md` (see SKILL.md → Codex 役の呼び出し). Every round is a **fresh, self-contained call**.

## Prompt Template

```markdown
<!-- agent-dialectics-role: dialectic-loop/induction-r{{ROUND}} -->
Answer in {{CONVERSATION_LANGUAGE}}. Do not use web search. This is read-only analysis — do not modify any file.

You are the **inductive (empirical) role** in a Dialectic Loop. The deductive role
(another model) authored a hypothesis and predictions. Your job is to test them against
the real corpus and, crucially, to **hunt for counterexamples**. Do not flatter the
hypothesis — a counterexample you find is worth more than a confirmation.

**IMPORTANT**: Re-read all data from disk. Ignore any cached content. The corpus is large —
process it with scripts (node/python/ripgrep), never by reading raw dumps.

## Corpus

{{CORPUS_PATHS_AND_EXTRACTION_RULES}}
<!-- e.g. /home/.../**/*.jsonl, one JSON object per line; keep obj.type==='user' with
     obj.message; drop messages whose content is entirely tool_result; concat text parts;
     drop lines starting with <local-command|Caveat:|<command-|<task-notification|<bash- -->

## Hypothesis under test (H)

{{HYPOTHESIS}}

## Predictions to verify

{{PREDICTIONS_P1_PN}}
<!-- each with its 支持条件 / 反証条件 / Measure -->

## Prior rounds (verdicts and measurements)

{{PRIOR_ROUNDS}}
<!-- Round 1: write "none". Round 2+: paste verbatim, for every earlier round k, the state
     sections "Round k / Inductive — Evidence", "Round k / Arbitration / Scorecard" and
     "Round k / Arbitration / Disk recompute". Nothing from the "Abduction" section. -->
Prior measurements are for comparison only — re-measure everything from disk for this round;
do not copy earlier numbers.

## Your task

For **each** prediction:
1. Compute the **Measure** (a number: count / rate / ratio) by scripting over the corpus.
2. Quote **3–5 short verbatim instances** (trimmed) that illustrate the result.
3. **Actively search for counterexamples** to the prediction and report how many you found.
4. Render a verdict: **【支持 / 部分支持 / 反証】** with the number.

Then provide:

### 【帰納役の総合所見】
- How should H be updated based on the evidence?
- **2–3 nuances or counterexamples the deductive role likely missed** (this is the most
  valuable part — be specific, cite numbers/quotes, no sycophancy).

## Response format

\`\`\`markdown
**P1** 【支持/部分支持/反証】 measure=...  
- "quote" / "quote" / "quote"  
- counterexamples found: N (...)

**P2** ...

### 【帰納役の総合所見】
- update: ...
- missed #1: ...
- missed #2: ...
\`\`\`

---
status: stop
---
```

## Codex invocation (codex mode)

Run through `scripts/run-codex-role.sh` exactly as described in SKILL.md → Codex 役の呼び出し
(fresh, read-only, background). Write `inputs.json` alongside `prompt.md`, listing only the
allowed state sections (SKILL.md → Step 4 / Non-leak rule). On exit 0, read `answer.md` and
record `induction_thread_id: codex:<uuid>` from `meta.json`.

Round 2+ is **not** a continuation: it is a new fresh call whose prompt carries the current H,
the current predictions, the corpus rule, and the prior rounds' verdicts/measurements in the
"Prior rounds" section above.

## Abduction variant (`--abduce`) note

When the hypothesis was abduced by Codex (Phase 0), the inductive role still runs here as an
independent test — but with the following extra rules:

- **Fresh, isolated call.** Every induction call is separate from the abduction call, and its
  `threadId` must differ from `abduction_thread_id`. Fill the template only from the allowed
  state sections — **never** from `Abduction`, `Abduction / Candidates`, `Abduction / Selection`,
  or `frontmatter.original_claim`. Do not reveal that Codex authored H, nor the abduction
  call's candidates/rationale/confidence. The verifier should test H on its merits, blind to its origin.
- **Origin-neutral wording.** Replace the template's opening line ("The deductive role (another
  model) authored a hypothesis and predictions") with an origin-neutral one, e.g.
  *"The hypothesis (H) and predictions below were prepared outside this conversation."* Do not assert
  who authored H (Codex authored it in this variant; saying "another model" would be false).
- **Codex unavailable (exit 2) never degrades to claude-only** in this variant — the loop stops
  with `status: blocked_no_codex` (SKILL.md → Error Handling).
- The arbiter's disk recompute is mandatory in this variant, and same-corpus discovery→validation
  is marked `evidence_scope: exploratory_in_sample`.

## Quality bar

- A prediction reported without a number is **not** verified — push back / re-run.
- "部分支持" must state *which part* held and which did not (this is what the arbiter needs).
- If the inductive role cannot access the corpus, it must say so rather than guess.
