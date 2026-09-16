<!-- agent-dialectics-role: contradiction-lift/solver-b -->
Respond in the language of the user's conversation (Japanese). Do not use web search.

You are solving a question independently. You will NOT see any other
solution; answer on your own merits. Re-read any referenced files from disk.

## Decision Contract

**Question (Q):** 設定値の検証を起動時に一括で行う（fail-fast）か、各機能の初回利用時に遅延して行う（lazy）か。

**Success conditions:**
- 不正な設定による誤動作（誤った接続先への書き込み、認証の素通り）を利用者に届けない
- 設定不備による全面停止の時間を最小化する

**Constraints:**
- 起動 SLO は 2 秒
- 運用チームは 2 名、設定項目は約 60

**Immovable requirements:**
- 設定不備は必ずログに記録する

**Observable variables:**
- 設定項目ごとの依存機能、起動時間
- 過去 1 年の設定不備 12 件（うち複数機能が共有する項目での不備 3 件）

**Required decision format:** どの条件で起動時検証を選び、どの条件で遅延検証を選ぶかの決定規則

### Referenced files
- なし（抽象的な設計判断。ソルバーはディスクを読まない）

## Your task
Produce a structured solution using the schema below. Give the **decision rule**, not only a
conclusion. Be concrete and falsifiable; no hedging-to-the-middle.

## Output schema

```markdown
- **Conclusion**: {one-line answer to Q}
- **Decision rule f**: {the rule/procedure that produces the conclusion — "given <inputs>, choose <X> because <criterion>"}
- **Causal model**: {why this works — the mechanism, not just correlation}
- **Load-bearing assumptions**: {the premises that, if false, would change the conclusion — list them explicitly}
- **Invariants to protect**: {what must not be sacrificed}
- **Rejected alternatives**: {what you considered and discarded, with the reason}
- **Flip observation**: {the single observation that would flip your conclusion}
- **Confidence**: {low | medium | high} + {why}
```
