---
schema: devils-advocate/v2
task_id: 20260916-120000-10003
created: 2026-09-16T12:00:00Z
state_dir: __STATE_DIR__
target_root: __TARGET_ROOT__
proposal: "config.yaml をリクエスト毎に読む実装をやめ、起動時に 1 回読み込み SIGHUP で再読み込みする"
mode: codex
round: 1
max_rounds: 2
status: in_progress
verdict: pending
degraded: false
codex_call_failures: []
red_thread_ids:
  - r1: codex:0199a002-0000-4000-8000-000000000001
---

# Red Team Review: config.yaml をリクエスト毎に読む実装をやめ、起動時に 1 回読み込み SIGHUP で再読み込みする

## Overview

**Proposal:** config.yaml をリクエスト毎に読む実装をやめ、起動時に 1 回読み込み SIGHUP で再読み込みする
**Mode:** codex
**Max Rounds:** 2

## Context

### Proposal Summary
API サーバーはリクエストを処理するたびに config.yaml を読み込んでパースしている。これを起動時の 1 回に変え、設定変更は SIGHUP を受けたときに再読み込みする。

### Related Files
- src/config.js: 設定の読み込み（loadConfig）
- src/server.js: リクエストハンドラ（handleRequest）

### Relevant Excerpts
src/server.js:12-18
```js
async function handleRequest(req, res) {
  const config = await loadConfig("config.yaml"); // 毎回ディスクから読む
  const client = connect(config.upstream.url, { timeout: config.upstream.timeoutMs });
  ...
}
```

src/config.js:3-9
```js
export async function loadConfig(path) {
  const text = await fs.readFile(path, "utf8");
  return yaml.parse(text); // 検証なし
}
```

### Current State
1 リクエストあたり約 3 ms を設定の読み込みとパースに使っている。設定ファイルを編集すると次のリクエストから即時に反映される。インスタンスは 4 台。

### Proposed Change
起動時に loadConfig を 1 回呼び、結果をモジュール変数に保持する。SIGHUP ハンドラで loadConfig を再実行してモジュール変数を更新する。

## Snapshot

### Confirmed Points

### Unresolved Concerns
- R1-C1 (High) 再読み込み中に新旧設定が混在する
- R1-C2 (Medium) 不正な設定ファイルでの再読み込み失敗時の挙動が未定義
- R1-C3 (Low) 複数インスタンス間で再読み込みの反映が揃わない

### Rejected Ideas

## Debate Log

### Round 1

#### Blue Team (Claude)

**Position:**
config.yaml の読み込みを起動時の 1 回にし、SIGHUP で再読み込みする。リクエスト毎のディスク読み込みとパースをなくし、レイテンシを下げる。

**Key Points:**
1. 設定の読み込みとパースに 1 リクエストあたり約 3 ms かかっており、これがなくなる
2. 設定変更は週に 1 回程度で、即時反映の必要はない
3. SIGHUP による再読み込みは既存の運用手順（ログローテーション）と同じ操作で行える

#### Red Team (Codex)

### Red Team Critique (Round 1)

#### Key Concerns
1. **R1-C1 [Severity: High]** 再読み込み中に新旧設定が混在する
   - Issue: SIGHUP ハンドラが設定オブジェクトの項目を順に書き換えると、処理中のリクエストが新旧の値が混ざった状態を読む
   - Impact: 接続先とタイムアウト値が一時的に食い違い、断続的なエラーになる
   - Suggestion: 新しい設定オブジェクトを完全に構築・検証してから、参照を 1 回で差し替える

2. **R1-C2 [Severity: Medium]** 不正な設定ファイルでの再読み込み失敗時の挙動が未定義
   - Issue: 提案には SIGHUP 時に config.yaml のパースや検証が失敗した場合の扱いがない
   - Impact: プロセスが終了する、または不完全な設定で動き続ける
   - Suggestion: 検証に失敗したら旧設定を維持し、失敗をログとメトリクスで通知する

3. **R1-C3 [Severity: Low]** 複数インスタンス間で再読み込みの反映が揃わない
   - Issue: SIGHUP はプロセスごとに送る必要があり、一部のインスタンスだけ新設定になりうる
   - Impact: 同じリクエストがインスタンスによって異なる設定で処理される
   - Suggestion: 読み込んだ設定の世代（ハッシュ）をヘルスチェックで公開し、反映漏れを検出できるようにする

#### Open Questions
- 設定変更はどの程度の頻度で行われるか（再読み込みの仕組みが必要なほど頻繁か）
- 起動時 1 回の読み込みで、現在リクエスト毎に読んでいることで得ている即時反映は誰が必要としているか

### Round 2

#### Blue Team (Claude)

**Position:**
起動時 1 回の読み込みと SIGHUP での再読み込みを維持し、再読み込みを「新しい設定オブジェクトを構築・検証してから参照を 1 回で差し替える」方式に変更する。

**Key Points:**
1. 設定は不変オブジェクトとして扱い、リクエストは処理開始時に参照を 1 回だけ取得する
2. 再読み込み時の検証に失敗したら旧設定を維持してエラーログを出す
3. 設定変更の頻度は週 1 回程度で、即時反映を必要とする利用者はいない（運用チームに確認済み）

**Response to Concerns:**
- R1-C1 — accepted & changed: 検証済みの新オブジェクトへの参照の一括差し替えに変更した
- R1-C2 — accepted & changed: 検証失敗時は旧設定を維持しエラーログを出す（通知方法は未定）
- R1-C3 — rebutted: 4 台すべてに SIGHUP を送る手順を運用手順書に追加するので、仕組みは不要
