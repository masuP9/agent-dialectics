# ゲート A 受け入れチェックリスト（PR1）

> 2 回目（再試験）の記録。1 回目（2026-09-16、F-1・F-2 が不合格）の記録は [records/gate-a-run1.md](records/gate-a-run1.md)。

プラン `planning-rename-20260916-015318` の Phase 1 step 8（WBS 4 / 5 / 5b / 11）の受け入れ記録。
**A-1**（mock companion による分岐検証。実モデル不使用）→ **A-2**（実モデルで最小回数の完走）の順に実施し、各項目の「合否」欄に `合格` / `不合格` / `対象外`（理由をメモ欄に）を記入する。

wrapper の契約（answer.md == rawOutput、失敗時に answer.md を書かない、`--fresh` 固定、`--model` / `--effort` の透過など）は `bash scripts/test-run-codex-role.sh` で担保済みのため、ゲートでは再検証しない（下記 0-0 で全パスだけ確認する）。

## 実施記録

| 項目 | 値 |
|---|---|
| 実施日 | 2026-09-16 |
| 実施者 | masup9（準備・確認の補助: Claude Code） |
| 対象コミット（`git -C "$REPO" rev-parse HEAD`） | `73de63c912541d02c692e7c86536625a14d01138`（branch `feat/pr1-run-codex-role`、未コミットの変更 121 件を含む作業ツリーで実施。2 回目は縮退警告の修正（SKILL.md「縮退時の警告は、縮退した時点で出す（必須）」）を含む） |
| codex-cli（`codex --version`） | codex-cli 0.154.0 |
| codex-plugin-cc companion のバージョン | codex@openai-codex 1.0.6 |
| config.toml の model / effort | `gpt-6-astra` / `low` |
| 作業用リポジトリ（`$SCRATCH`） | `/home/masup9/scratch/gate-a-target`（`$BASE` = `/home/masup9/.local/state/agent-dialectics/gate-a-target-f3b6cc81`。1 回目の state は `…-f3b6cc81-run1`、`$ARGS_LOG` は `/tmp/gate-a-mock-args.run1.jsonl` に退避し、2 回目は空の `$BASE` から開始） |

---

## 0. 共通準備

### 0-0. 事前確認

| ID | 項目 | 合否 | メモ |
|---|---|---|---|
| 0-0a | `bash "$REPO/scripts/test-run-codex-role.sh"` が全パス | 合格 | passed=49 failed=0 |
| 0-0b | `bash "$REPO/scripts/lint-plugin.sh"` が全パス | 合格 | errors=0, warnings=0 |
| 0-0c | 旧 0.26.0 がアンインストール済み（`/plugin` 一覧に `codex-collab@codex-collab` がない） | 合格 | 1 回目から変更なし（installed_plugins.json に登録なし） |

### 0-1. 変数と作業用リポジトリ

以下は Claude Code の外の通常のターミナルで実行する。

```bash
REPO=/home/masup9/ghq/github.com/masuP9/codex-collab
SCRATCH="$HOME/scratch/gate-a-target"          # プラグインのリポジトリとは別の git リポジトリ
mkdir -p "$SCRATCH" && git -C "$SCRATCH" init -q
cp "$REPO"/tests/acceptance/fixtures/corpus/*.sh "$SCRATCH"/   # A-2 strong-inference の題材
git -C "$SCRATCH" add -A && git -C "$SCRATCH" commit -qm "gate A target"
git -C "$SCRATCH" status --porcelain > /tmp/gate-a-status-before.txt   # 対象リポジトリ不変の確認用（空のはず）
ARGS_LOG=/tmp/gate-a-mock-args.jsonl           # mock が受け取った argv と prompt を 1 行ずつ記録
```

### 0-2. state dir（SKILL.md と同じ計算）

```bash
ROOT="$(git -C "$SCRATCH" rev-parse --show-toplevel)"
SLUG="$(basename "$ROOT")-$(printf '%s' "$ROOT" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
BASE="${XDG_STATE_HOME:-$HOME/.local/state}/agent-dialectics/$SLUG"
echo "$BASE"
```

- `$SCRATCH` がシンボリックリンクを含むパスだと、Claude 側の `git rev-parse --show-toplevel` と値がずれることがある。0-3 で Claude に `ROOT` を表示させ、上の値と一致することを確認する
- 既存の state と混ざらないよう、A-1 の前に `ls "$BASE"` が空（または存在しない）ことを確認する

### 0-3. 起動コマンド（A-1: mock companion）

```bash
cd "$SCRATCH" && \
CODEX_COMPANION_PATH="$REPO/tests/acceptance/mock-companion.mjs" \
MOCK_FIXTURES_DIR="$REPO/tests/acceptance/fixtures/responses" \
MOCK_ARGS_LOG="$ARGS_LOG" \
claude --plugin-dir "$REPO"
```

- 以降「0-3 の起動」と書いたら上記。`MOCK_FIXTURES_DIR` などの差し替えは各項目に書く
- 環境変数は起動時に決まる。値を変える項目では**セッションを終了して起動し直す**

### 0-4. 途中状態 fixture の配置

`tests/acceptance/fixtures/states/<method>/<task-id>/` を state dir にコピーする（devils-advocate は frontmatter の `__STATE_DIR__` / `__TARGET_ROOT__` を置換する）。

```bash
seed() {  # seed <method> <task-id>
  local src="$REPO/tests/acceptance/fixtures/states/$1/$2" dest="$BASE/$1/$2"
  mkdir -p "$BASE/$1" && cp -R "$src" "$dest"
  sed -i.bak "s#__STATE_DIR__#$dest#; s#__TARGET_ROOT__#$ROOT#" "$dest/state.md" && rm -f "$dest/state.md.bak"
  echo "$dest"
}
```

| fixture | 内容 | 用途 |
|---|---|---|
| `devils-advocate/20260916-120000-10001` | ラウンド 1 完了（`round: 1`, `max_rounds: 2`、Snapshot に R1-C1〜C3、`red-r1-1/` は DONE 済み） | A-1-DA-2, A-1-R-2 |
| `devils-advocate/20260916-120000-10002` | 10001 + Round 2 Blue Team 記入済み、`red-r2-1/status.json` が `running` かつ pid 4194303（DONE なし） | A-1-R-3（unknown） |
| `devils-advocate/20260916-120000-10003` | 10001 + Round 2 Blue Team 記入済み、`red-r2-1/` が `failed`（exit 4、error.log あり） | A-1-R-4（failed） |
| `contradiction-lift/20260916-120000-20001` | `state: mapped`、`anonymization_key: "X=A,Y=B"`、`solver-b-1/` と `mapper-1/` は DONE 済み、Ledger は normative の load-bearing 1 件 + constraint + semantic（empirical なし） | A-1-CL-2, A-1-CL-3 |

10002 を使う前に、この環境で pid 4194303 が存在しないことを確認する: `kill -0 4194303` がエラーになること。

### 0-5. 再開の依頼文

SKILL.md には再開用の引数がないため、新しいセッションで次のように依頼する（新規 task を作らせない）:

> `/codex-collab:<method>` の Compact Recovery に従って、state dir `<dest>` の中断したタスクを再開してください。新しいタスクは作らないでください。

### 0-6. 固定応答 fixture

`MOCK_FIXTURES_DIR/<method>/<role>.json` を、prompt.md 1 行目のマーカー `<!-- agent-dialectics-role: <method>/<role> -->` で選ぶ（`<role>` はラウンド接尾辞込み、例 `red-r2`）。threadId はすべて固定で互いに異なる。

| root | method / role | threadId 末尾 | 内容 |
|---|---|---|---|
| `responses` | strong-inference / `hypothesis-r1` | `a001-…0001` | 競合仮説 H1〜H3 |
| `responses` | strong-inference / `review` | `a001-…0002` | Confidence Medium の Review |
| `responses` | devils-advocate / `red-r1` | `a002-…0001` | R1-C1（High）/ R1-C2（Medium）/ R1-C3（Low） |
| `responses` | devils-advocate / `red-r2` | `a002-…0002` | Prior Findings Status に R1-C1 Resolved / R1-C2 Partially Resolved / R1-C3 Unresolved、R2-C1、**Decision: CONDITIONAL** |
| `responses` | dialectic-loop / `abduction` | `a003-…0001` | Candidate H1〜H3（H3 が tension-bearing） |
| `responses` | dialectic-loop / `induction-r1` | `a003-…0002` | H3 に対する P1〜P4（数値は corpus の実測値） |
| `responses` | dialectic-loop / `induction-r2` | `a003-…0003` | 精緻化した H′ に対する P1〜P3 |
| `responses` | contradiction-lift / `solver-b` | `a004-…0001` | 遅延検証（lazy）の封印解 |
| `responses` | contradiction-lift / `mapper` | `a004-…0002` | normative（load-bearing）+ constraint + semantic |
| `responses` | contradiction-lift / `preserve-b-steelman` `preserve-b-review`（accept）`preserve-b-repair` `preserve-b-rereview`（accept） | `a004-…0003`〜`0006` | Phase 4 の Codex 側当事者 |
| `responses` | contradiction-lift / `lift-r1` `lift-r2` | `a004-…0007` / `0008` | 選択機構 |
| `responses` | contradiction-lift / `audit-r1` | `a004-…0009` | **7/7 pass, causal yes → accepted** |
| `responses-aporia` | contradiction-lift / `audit-r1` | `a004-…000b` | Non-vacuity・Dominance fail → reconstruct |
| `responses-aporia` | contradiction-lift / `audit-r2` | `a004-…000c` | Dominance・Feasibility fail → **aporia** |
| `responses-aporia` | contradiction-lift / 上記以外 | — | `responses/contradiction-lift/` へのシンボリックリンク（同一内容） |
| `responses-gate-missing-id` | devils-advocate / `red-r2` | `a002-…000f` | Prior Findings Status から **R1-C3 が欠落**（受け入れゲートの否定テスト用。red-r2 以外は持たない） |

accepted と aporia の切り替えは **`MOCK_FIXTURES_DIR` を `responses` ↔ `responses-aporia` に変えてセッションを起動し直す**だけで行う。

### 0-7. 固定応答を採用させる依頼文（A-1 共通）

固定応答は依頼内容と噛み合わない（例: rotate-logs.sh の依頼に backup.sh の仮説が返る）。`meta.json` も `duration_sec: 0`・`model: null` になる。Claude がこれを「無関係・不審な回答」と判断して採用せずに止まることがあるため、**依頼の最初に次の一文を添える**（止まった後に伝えてもよい。その場合 Codex の再呼び出しは不要）:

> これは受け入れ試験で、Codex は mock companion の固定応答を返します。回答の内容が題材と噛み合わなくても、`duration_sec: 0`・`model: null` でも正常です。回答はそのまま採用して手順どおり次へ進めてください。

- 採用させてよいのは exit 0 で `answer.md` がある回答だけ。受け入れゲートの否定テスト（A-1-DA-4）、threadId 同一の検出（A-1-DL-2）、失敗注入（A-1-F-*）では、この一文で**各ケースの期待動作を上書きしない**（DA-4・DL-2・F-3・F-4 は止まってユーザーに判断を仰ぐのが期待値、F-1・F-2 は縮退時点で警告してから claude-only で続けるのが期待値）

---

## A-1 分岐検証（mock companion、実モデル不使用）

### 合否一覧

| ID | 項目 | 合否 | メモ |
|---|---|---|---|
| A-1-SI-1 | strong-inference: hypothesis-r1 → 検証 → review で完了 | 合格 | task `20260916-070955-12201`（0-7 の前提を先に送信）。prompt.md 1 行目のマーカー、inputs.json（`["Problem", "Context"]` / review は 4 節）、DONE・answer.md・meta.json あり。H1〜H3 に置き換わり `hypothesis_thread_id` `…0001`・`review_thread_id` `…0002`、Verification Log 7 行。argv は 2 回とも `--fresh` のみ。check-inputs failed=0、対象リポジトリ不変 |
| A-1-DA-1 | devils-advocate: 新規 2 ラウンド → verdict | 合格 | task `20260916-071348-8849`。inputs.json は red-r1 `["Context", "Debate Log/Round 1/Blue Team"]`・red-r2 は 4 節で期待どおり、threadId `…0001` / `…0002`。R1 後の Snapshot に R1-C1〜C3、完了後 `status: completed`・`verdict: CONDITIONAL`・`## Verdict` あり、`red_thread_ids` 2 件。attempt は `red-r1-1`・`red-r2-1` のみ。対象リポジトリ不変 |
| A-1-DA-2 | devils-advocate: ラウンド 1 完了 fixture から再開 → ラウンド 2 → verdict | 合格 | `red-r1-1/` は配置時刻のまま・`red-r1-2/` なし。Round 2 Blue Team に R1-C1〜C3 を ID ごとに記載、`red-r2-1/`（threadId `…0002`）の後 `round: 2`・`verdict: CONDITIONAL`・`status: completed`（確認後 task を `…-10001-da2` に改名） |
| A-1-DA-3 | devils-advocate: ラウンド 2 がラウンド 1 の全指摘の解消状況に言及し、状態に反映される | 合格 | DA-1・DA-2 の両方で確認。red-r2-1/prompt.md に Snapshot・前ラウンド批評・全 ID の状態を書く指示あり。Prior Findings Status に R1-C1 Resolved / C2 Partially Resolved / C3 Unresolved が記録され、Snapshot は R1-C1 が Confirmed、R1-C2・C3・R2-C1 が Unresolved。最終レポートに各 ID の状態あり（見出しは実行セッションの出力スタイルで言い換え） |
| A-1-DA-4 | devils-advocate: ID 欠落の red-r2 を受け入れゲートが拒否する | 合格 | `red-r2-1/` は exit 0・DONE あり（threadId `…000f`）。受け入れゲートで「Prior Findings Status に R1-C3 がない」と示し、呼び直すか進めるかをユーザーに質問（未回答で終了）。`round: 1`・`verdict: pending`・`red-r2-2/` なし（確認後 task を `…-10001-da4` に改名） |
| A-1-DL-1 | dialectic-loop `--abduce`: abduction と induction が別 role-attempt・別 threadId | 合格 | task `20260916-072419-22796`。`abduction-1/`・`induction-r1-1/`・`induction-r2-1/` が別ディレクトリで threadId `…0001`/`…0002`/`…0003`、`abduction_thread_id`・`induction_thread_id`（最新ラウンドの `…0003`）を `codex:` 付きで記録。abduction の inputs.json は `["frontmatter.corpus", "frontmatter.original_claim"]`、induction の prompt.md に候補・選定・出どころの記述 0 件。Arbitration に Disk recompute、`evidence_scope: exploratory_in_sample`、induction-r2 の inputs.json に Round 1 の Evidence・Scorecard・Disk recompute。2 ラウンド完走、inputs.json 3 件は許可リスト内。1 回目の依頼は前提ファイルの作り忘れで前提なしで届いたため、task 作成前に中断して起動し直した |
| A-1-DL-2 | dialectic-loop `--abduce`: threadId が同一なら結果不正として進めない | 合格 | task `20260916-073102-26118`（`MOCK_THREAD_ID=…00ff`）。induction-r1-1 完了後に abduction と同一 threadId を「exit 5 相当の不正」として `codex_call_failures` に記録、`induction_thread_id: ""`・`phase: inductive`・Arbitration 節なしでユーザーに確認（未回答で終了） |
| A-1-CL-1 | contradiction-lift: 開始 → sealed → mapped（solver-b / mapper の非漏洩と threadId 相違） | 合格 | task `20260916-073443-32213`、`anonymization_key: "X=A,Y=B"`。会話記録で solver-b の Bash と Solver A の Agent が同一メッセージ、Solver A が返るまで solver-b の回答を開かない。`solver-b-1/inputs.json` は `["Decision Contract"]`、`mapper-1/inputs.json` は Contract + X / Y、prompt.md に相手解・`Sealed Solutions`・モデル名なし。argv は mapper のみ `--model gpt-5.6-luna --effort low`、threadId `…0001` ≠ `…0002`、`state: mapped`。1 回目の所見だった `created` は今回 `2026-09-15T22:34:43Z` で正しい UTC |
| A-1-CL-2 | contradiction-lift: mapped fixture → Preservation → Lift → Audit → **accepted** | 合格 | 1 回で到達（0-7 + Lift/Audit とも Codex + Claude 側 review accept の指示）。Adjudication は #3 semantic を用語正規化、#2 constraint を Contract の起動 SLO と照合、#1 normative を Preservation へ、`empirical_arbiter: not_applicable`・`arbiter-d*/` なし。`preserve-b-steelman-1/inputs.json` に `Preservation/X-steelmans-Y` なし、`preserve-b-review-1/`（`…0004`）は accept で repair なしの経路、Certification は両方 certified。`lift-r1-1/`（`…0007`、`lift_attempts: 1`）→ `audit-r1-1/`（`…0009`）、`state: accepted`・`outcome: lifted`、レポートは「Contradiction Lift — ACCEPTED」と `Audit: 7/7 passed, causal check = yes`。inputs.json 6 件は許可リスト内、対象リポジトリ不変（確認後 task を `…-20001-cl2` に改名） |
| A-1-CL-3 | contradiction-lift: mapped fixture → Lift ×2 → Audit ×2 → **aporia** | 合格 | `responses-aporia` で実施。`lift-r2-1/inputs.json` に `Lift/Attempt 1` と `Audit/Attempt 1`（`lift_attempts: 2`）、`audit-r2-1/inputs.json` は `Lift/Attempt 2` のみ。threadId lift `…0007`/`…0008`・audit `…000b`/`…000c`（frontmatter に attempt 1 の値をコメントで併記）。`state: aporia`・`outcome: aporia`、レポートは「Contradiction Lift — APORIA（止揚できず）」で 2 回とも Dominance 不合格を明示し、単純な折衷を統合として報告していない。inputs.json 8 件は許可リスト内、対象リポジトリ不変（確認後 task を `…-20001-cl3` に改名）。組み合わせ上書きなしの確認は未実施 |
| A-1-R-1 | 中断再開: 実行中に終了 → 新セッションで重複投入しない | 合格 | `MOCK_DELAY_SEC=180`。`red-r2-1/status.json` が running（pid 108538）になった時点で Ctrl+C →「Exit and stop tasks」で終了。終了後 `kill -0` は失敗、status は running のまま・DONE なし。再開したセッションは unknown と判定して再投入の可否を質問（未回答で終了）、`red-r2-2/` なし・`red-r2-1/` は上書きなし、`round: 1`・`verdict: pending`（確認後 task を `…-10001-r1` に改名） |
| A-1-R-2 | 再開規則: running かつ pid 生存 → 待機 | 合格 | `rm` が禁止のため status.json は移動で置き換え、wrapper を `MOCK_DELAY_SEC=300` で起動（pid 110555）。再開したセッションは pid 生存を確認して再投入せず待機（`red-r2-2/` なし）、完了後に同じ `answer.md` で `round: 2`・`verdict: CONDITIONAL`・`status: completed`（確認後 task を `…-10002-r2` に改名） |
| A-1-R-3 | 再開規則: running だが pid 消滅・DONE なし → unknown としてユーザー確認 | 合格 | `kill -0 4194303` が失敗することを確認して配置。「実行中のまま実体が消えた」と判定し、red-r2-2 での再投入 / 中断のまま / 打ち切りをユーザーに質問（未回答で終了）。`red-r2-2/` なし、`round: 1`・`verdict: pending`（確認後 task を `…-10002-r3` に改名） |
| A-1-R-4 | 再開規則: failed → ユーザー判断 | 合格 | `red-r2-1/` の failed・exit 4 と error.log を示し、`codex_call_failures` に `{role: red-r2, exit: 4, attempt: 1}`。自動再実行・自動縮退なしで、Codex で再投入 / claude-only（exit 4 は本来縮退理由でないと明示）/ 打ち切りをユーザーに質問（未回答で終了）。`red-r2-2/` なし、`round: 1`・`degraded: false`（確認後 task を `…-10003-r4` に改名） |
| A-1-F-1 | 失敗注入 exit 2（companion 不在）→ 警告付き縮退 `degraded: true` | 合格 | task `20260916-081500-10802`。`error.log` に `CODEX_COMPANION_PATH not found: /nonexistent`・answer.md なし、`degraded: true`・`mode: claude-only`・`codex_call_failures` に `{role: hypothesis-r1, exit: 2, attempt: 1}`。**1 回目の不合格点が解消**: run-codex-role.sh の exit 2 の直後、次のツール呼び出しより前に「⚠️ Codex を使えないため…（`degraded: true`）」の警告テキストを出し、理由は未取得のため「詳細未確認」と書いてから調査して補足。完了レポートの確かさに「独立レビューなし（claude-only に縮退）」あり |
| A-1-F-2 | 失敗注入 exit 2（setup `codex.available:false`）→ 同上 | 合格 | task `20260916-081940-1229`（依頼文に「一般的な設計として議論」を添えて 1 回目のような対象コード確認の質問を回避）。`red-r1-1/error.log` に `Codex not ready`、`degraded: true`・`mode: claude-only`・`codex_call_failures` に `{role: red-r1, exit: 2, attempt: 1}`、Red Team 見出しは両ラウンドとも `(Claude)`、完走して `verdict: CONDITIONAL`。**1 回目の不合格点が解消**: 終了コードを知った直後（完了通知を読んだ次）に「⚠️ Codex を使えないため…（`degraded: true`）」を出し、その後に Claude サブエージェントを起動。最終レポートにも「批評役も Claude。別モデルによる独立した裏取りではない」と明記 |
| A-1-F-3 | 失敗注入 exit 2 × `--abduce` → `blocked_no_codex` で停止 | 合格 | task `20260916-083050-16856`。`abduction-1/` は exit 2（`Codex not ready`）、`status: blocked_no_codex`・`degraded: false`・`mode: codex`・`codex_call_failures` に `{role: abduction, exit: 2, attempt: 1}`、`abduction_status: pending` で候補 0 件（claude-only に縮退しない）。再試行 / 中止 / 既定の形への切り替えをユーザーに質問（未回答で終了）。`--mode claude-only` / `--rotate` との組み合わせエラー（任意）は未実施 |
| A-1-F-4 | 失敗注入 exit 5（空 rawOutput）→ 次相へ進まない | 合格 | strong-inference（task `20260916-083744-20955`）。`hypothesis-r1-1/` は failed・exit 5、`error.log` に `invalid result: empty rawOutput`、answer.md なし。`## Hypotheses` は `(Pending generation)`・`iteration: 0`・`hypothesis_thread_id: ""`、`degraded: false`・`mode: codex`、`-2` の attempt なしでユーザーに判断を依頼。1 回目の投入は前セッションが閉じきっておらず `MOCK_SETUP_JSON` 付きの環境に届いたため（task `…-083407-17907-misfire` に退避）、起動し直して再実施 |
| A-1-N-1 | 非漏洩: 全 inputs.json が許可リスト内 | 合格 | `$BASE` 配下の全 18 task で `failed=0`、checked=0 の task なし。補助: `Sealed Solutions` を含む prompt.md 0 件、induction の prompt.md に候補・選定の記述 0 件、audit-r1/r2 の inputs.json 3 件とも `Audit/*`・他回の `Lift/Attempt` なし、`red-r3` 以降の attempt なし |
| A-1-G-1 | A-1 全体で対象リポジトリの git status 不変、`$SCRATCH/tmp` なし | 合格 | A-1 終了時点で `git status --porcelain` が基準（空）と差分なし、`$SCRATCH/tmp` なし |

### A-1-SI-1 strong-inference

- 起動: 0-3
- 依頼: `/codex-collab:strong-inference rotate-logs.sh が "rotated N file(s)" を出さずに非0終了することがある`（0-7 の一文を添える。固定応答の仮説は backup.sh の月初失敗を前提にしており、題材と無関係に見える）
- 観察:
  - [ ] `$BASE/strong-inference/<task-id>/hypothesis-r1-1/` に `prompt.md`（1 行目 `<!-- agent-dialectics-role: strong-inference/hypothesis-r1 -->`）、`inputs.json`（`["Problem", "Context"]`）、`answer.md`、`meta.json`、`DONE`
  - [ ] state.md の `## Hypotheses` が fixture の H1〜H3 に置き換わり、`hypothesis_thread_id: codex:0199a001-0000-4000-8000-000000000001`
  - [ ] 検証は Claude が実行し、Verification Log に行が増える（mock の仮説と題材が噛み合わなくてよい。どれかを支持/棄却して Step 7 へ進めるよう指示してよい）
  - [ ] `review-1/` の `inputs.json` が `["Problem", "Context", "Hypotheses", "Verification Log"]`、`review_thread_id: codex:0199a001-0000-4000-8000-000000000002`
  - [ ] `$ARGS_LOG` の各 task 行の argv に `--fresh` があり、`--model` / `--effort` がない

### A-1-DA-1 devils-advocate（新規）

- 起動: 0-3
- 依頼: `/codex-collab:devils-advocate --max-rounds 2 config.yaml をリクエスト毎に読む実装をやめ、起動時に 1 回読み込み SIGHUP で再読み込みする`
- 観察:
  - [ ] `red-r1-1/inputs.json` が `["Context", "Debate Log/Round 1/Blue Team"]`
  - [ ] ラウンド 1 後の Snapshot / Unresolved Concerns に R1-C1〜R1-C3、`round: 1`
  - [ ] `red-r2-1/inputs.json` が `["Context", "Snapshot", "Debate Log/Round 1/Red Team", "Debate Log/Round 2/Blue Team"]`
  - [ ] 完了後 `status: completed`、`verdict: CONDITIONAL`、`## Verdict` 節あり、`red_thread_ids` に r1 / r2 の 2 件（`…a002-…0001` / `…0002`）
  - [ ] `red-r1-1` と `red-r2-1` 以外の attempt ディレクトリがない（自動再実行なし）

### A-1-DA-2 devils-advocate（ラウンド 1 完了 fixture から再開）

- 配置: `DEST=$(seed devils-advocate 20260916-120000-10001)`
- 起動: 0-3、依頼: 0-5（method = devils-advocate、dest = `$DEST`）
- 観察:
  - [ ] Round 1 を再実行しない（`red-r1-1/` はそのまま、`red-r1-2/` ができない）
  - [ ] Claude が Round 2 Blue Team を書き、`Response to Concerns` に R1-C1〜C3 を ID ごとに記載
  - [ ] `red-r2-1/` が作られ、終了後 `round: 2`、`verdict: CONDITIONAL`、`status: completed`

### A-1-DA-3 devils-advocate: ラウンド 1 指摘の解消状況

A-1-DA-1 と A-1-DA-2 の `red-r2-1/` で確認する。

- [ ] `red-r2-1/prompt.md` に Snapshot（Unresolved Concerns に R1-C1〜C3）と前ラウンドの Red Team 批評が貼られ、「Unresolved Concerns の全 ID の状態を Prior Findings Status に書く」指示がある（fresh 呼び出しでも前ラウンド文脈が再投入されている）
- [ ] `answer.md` の Prior Findings Status が R1-C1 / R1-C2 / R1-C3 をすべて含み、受け入れゲートを通過して state.md の Round 2 Red Team に記録された
- [ ] Snapshot 更新: R1-C1 が Confirmed Points、R1-C2（Partially Resolved）と R1-C3（Unresolved）と R2-C1 が Unresolved Concerns
- [ ] 最終レポートの Key Concerns Raised に各 ID の Status が載る
- 実モデルでの確認（任意、利用量に余裕があれば）: A-2 と同じ起動で devils-advocate を `--max-rounds 2` で 1 回完走し、ラウンド 2 の実回答が R1 の全 ID に状態を付けていることを確認する

### A-1-DA-4 devils-advocate: 受け入れゲートの否定テスト

- 配置: `DEST=$(seed devils-advocate 20260916-120000-10001)`（A-1-DA-2 と別の `$BASE` を使うか、先に A-1-DA-2 の task を削除しておく）
- 起動: 0-3 の `MOCK_FIXTURES_DIR` を `$REPO/tests/acceptance/fixtures/responses-gate-missing-id` に替える。依頼: 0-5
- 観察:
  - [ ] `red-r2-1/` は exit 0（DONE あり）だが、Claude が「R1-C3 が Prior Findings Status にない」と示してユーザーに確認する
  - [ ] ユーザーが指示するまで `round: 1` のまま、`verdict: pending`、`red-r2-2/` を自動で作らない

### A-1-DL-1 dialectic-loop `--abduce`

- 起動: 0-3
- 依頼: `/codex-collab:dialectic-loop --abduce --corpus "$REPO/tests/acceptance/fixtures/corpus/*.sh" --max-rounds 2`（`$REPO` は展開した絶対パスで書く）
- Phase 0b では **Candidate H3**（エラー終了の die() 集約）を選ぶ。induction の固定応答は H3 向けの測定値
- 観察:
  - [ ] `abduction-1/` と `induction-r1-1/` が別ディレクトリ
  - [ ] `abduction-1/meta.json` の threadId `0199a003-0000-4000-8000-000000000001` と `induction-r1-1/meta.json` の `…0002` が異なり、state.md の `abduction_thread_id` / `induction_thread_id` にそれぞれ `codex:` 付きで記録
  - [ ] 候補が `## Abduction / ### Candidates` に書かれた**後で** `abduction_status: done`
  - [ ] `abduction-1/inputs.json` が `["frontmatter.corpus", "frontmatter.original_claim"]`
  - [ ] `induction-r1-1/inputs.json` に `Abduction` 系・`frontmatter.original_claim` がなく、`prompt.md` に候補一覧・選定理由・「Codex が作った」「another model」の記述がない（origin-neutral の冒頭）
  - [ ] Arbitration に `#### Disk recompute`（corpus を実際に再計測）と `evidence_scope: exploratory_in_sample`
  - [ ] ラウンド 2 に進んだ場合は `induction-r2-1/`（threadId `…0003`）で、inputs.json に `Round 1 / Inductive — Evidence` / `Round 1 / Arbitration / Scorecard` / `Round 1 / Arbitration / Disk recompute` が入る。収束してラウンド 1 で終わっても合格（メモ欄に記録）

### A-1-DL-2 dialectic-loop: threadId 同一の検出

- 起動: 0-3 に `MOCK_THREAD_ID=0199a003-0000-4000-8000-0000000000ff` を追加（全呼び出しが同じ threadId を返す）
- 依頼: A-1-DL-1 と同じ（H3 を選ぶ）
- 観察:
  - [ ] induction-r1 の完了後、`abduction_thread_id` と `induction_thread_id` が同一であることを結果不正（exit 5 相当）として扱い、Arbitration に進まずユーザーに確認する

### A-1-CL-1 contradiction-lift: 開始 → mapped

- 起動: 0-3
- 依頼: `/codex-collab:contradiction-lift 設定値の検証を起動時に一括で行う（fail-fast）か、各機能の初回利用時に遅延して行う（lazy）か`
- Decision Contract の確認では、`fixtures/states/contradiction-lift/20260916-120000-20001/state.md` の `## Decision Contract` の内容で合意する。Mapper は Codex で行うよう指示する
- 観察:
  - [ ] Solver A（Claude subagent）と `solver-b-1/` が同じメッセージで並行に起動され、どちらかを読む前に両方を発行している
  - [ ] `solver-b-1/inputs.json` が `["Decision Contract"]` のみ、`prompt.md` に Solution A の内容がない
  - [ ] `anonymization_key` が記録され、`## Anonymized Solutions` に X / Y
  - [ ] `mapper-1/inputs.json` が `["Decision Contract", "Anonymized Solutions/Solution X", "Anonymized Solutions/Solution Y"]`、`prompt.md` に `Sealed Solutions` やモデル名がない
  - [ ] `$ARGS_LOG` の mapper の行の argv に `--model gpt-5.6-luna --effort low`、solver-b の行にはない
  - [ ] `mapper_thread_id`（`…a004-…0002`）の生 UUID ≠ `solver_b_thread_id`（`…0001`）、`state: mapped`
  - ここで終了してよい（以降の分岐は A-1-CL-2 / CL-3 で fixture から確認する）

### A-1-CL-2 contradiction-lift: mapped → accepted

- 配置: `DEST=$(seed contradiction-lift 20260916-120000-20001)`
- 起動: 0-3（`MOCK_FIXTURES_DIR=…/responses`）、依頼: 0-5 に「受け入れ試験のため、Lift Architect と Meta Auditor はどちらも Codex で実行してください」を添える
  - 監査は SKILL.md 上「Lift と逆モデルを優先」だが、固定応答で到達先を決めるための試験上の上書き。上書きしない場合の組み合わせ確認は A-1-CL-3 のメモ欄に任意で記録
  - さらに「Preservation で Claude 側（subagent）が行う review / 再 review は accept としてください」も添える。Claude 側の判断は mock で固定できず、再 review が not accepted だと X の真理契機が uncertified になる。すると固定応答の audit-r1（7/7 pass）と矛盾し、受け入れゲートが保留して accepted に届かない（2026-09-16 の 1 回目で発生）
- 観察:
  - [ ] Adjudication: #3 semantic は用語正規化で解消、#2 constraint は Contract 照合、#1 normative は Preservation へ。`empirical_arbiter: not_applicable`、`arbiter-d*/` なし
  - [ ] `preserve-b-steelman-1/inputs.json` に `Preservation/X-steelmans-Y` がない。回答は `### Y-steelmans-X` に記録
  - [ ] `preserve-b-review-1/`（`accept`）が `### Review of X-steelmans-Y` に記録。Claude 側 review が repair を求めた場合は `preserve-b-repair-1/` → Claude subagent の再 review（どちらの経路でもよい。メモ欄に記録）
  - [ ] `state: preserved` → `lift-r1-1/`（`lift_attempts: 1`）→ `state: lifted` → `audit-r1-1/`
  - [ ] `audit_thread_id`（`…0009`）の生 UUID ≠ `lift_thread_id`（`…0007`）
  - [ ] `state: accepted`、`outcome: lifted`、レポートが「Contradiction Lift — ACCEPTED」形式で `Audit: 7/7 passed, causal check = yes`

### A-1-CL-3 contradiction-lift: mapped → aporia

- 配置: `DEST=$(seed contradiction-lift 20260916-120000-20001)`（A-1-CL-2 の task を別名に退避するか削除してから）
- 起動: 0-3 の `MOCK_FIXTURES_DIR` を `$REPO/tests/acceptance/fixtures/responses-aporia` に替える。依頼は A-1-CL-2 と同じ（`max_lift_attempts: 2` のまま）
- 観察:
  - [ ] `audit-r1-1/` の fail（Non-vacuity・Dominance）を受けて Step 7 に戻り、`lift-r2-1/` の inputs.json に `Lift/Attempt 1` と `Audit/Attempt 1` が入る（`lift_attempts: 2`）
  - [ ] `audit-r2-1/inputs.json` に `Audit/Attempt 1` と `Lift/Attempt 1` がない（`Lift/Attempt 2` のみ）
  - [ ] `state: aporia`、`outcome: aporia`、レポートが「Contradiction Lift — APORIA (not lifted)」形式で、2 回とも失敗したテスト（Dominance）を挙げる
  - [ ] 平均的な折衷案を「統合」として報告していない

### A-1-R 中断と再開（WBS 4）

#### A-1-R-1 実行中の中断 → 新セッション

- 配置: `DEST=$(seed devils-advocate 20260916-120000-10001)`
- 起動: 0-3 に `MOCK_DELAY_SEC=180` を追加。依頼: 0-5
- 手順:
  1. `red-r2-1/status.json` が `"state": "running"` になったら（Blue Team 記入後）、応答を待たずに Claude セッションを終了する（`/exit`）
  2. ターミナルで `cat "$DEST/red-r2-1/status.json"` と `kill -0 <pid>; echo $?` を記録する
  3. 同じ環境変数で起動し直し、0-5 で再開を依頼する
- 期待:
  - [ ] pid が生存していた場合: 「完了待ち」と判断し、`red-r2-2/` を作らない。mock の遅延明けに `DONE` ができたら `answer.md` を再利用して verdict まで進む
  - [ ] pid が消滅していた場合: `unknown` としてユーザーに再投入の可否を確認し、承認するまで `red-r2-2/` を作らない
  - [ ] どちらの場合も `red-r2-1/` を上書き・再利用して再実行しない（wrapper は status.json がある out-dir を exit 1 で拒否する）

#### A-1-R-2 running かつ pid 生存 → 待機（決定的に再現）

- 配置: `DEST=$(seed devils-advocate 20260916-120000-10002)` の後、生存 pid を作る:

  ```bash
  rm "$DEST/red-r2-1/status.json"
  CODEX_COMPANION_PATH="$REPO/tests/acceptance/mock-companion.mjs" \
  MOCK_FIXTURES_DIR="$REPO/tests/acceptance/fixtures/responses" MOCK_DELAY_SEC=300 \
  nohup "$REPO/scripts/run-codex-role.sh" --prompt-file "$DEST/red-r2-1/prompt.md" \
    --cwd "$ROOT" --out-dir "$DEST/red-r2-1" > /dev/null 2>&1 &
  ```

- 起動: 0-3、依頼: 0-5
- 期待:
  - [ ] `status.json` の pid が生存していると判定し、再投入せず完了を待つ（`red-r2-2/` なし）
  - [ ] 5 分後に `DONE` ができたら、その `answer.md` で Round 2 を記録して verdict まで進む

#### A-1-R-3 running だが pid 消滅・DONE なし → unknown

- 配置: `DEST=$(seed devils-advocate 20260916-120000-10002)`（`kill -0 4194303` がエラーになることを先に確認）
- 起動: 0-3、依頼: 0-5
- 期待:
  - [ ] `red-r2-1` を `unknown` と判定し、ユーザーに再投入してよいか確認する
  - [ ] 回答するまで `red-r2-2/` を作らず、`round: 1` のまま

#### A-1-R-4 failed → ユーザー判断

- 配置: `DEST=$(seed devils-advocate 20260916-120000-10003)`
- 起動: 0-3、依頼: 0-5
- 期待:
  - [ ] `red-r2-1/error.log`（exit 4、usage limit）を示し、自動再実行・自動縮退をせずにユーザーの判断を仰ぐ
  - [ ] 承認した場合のみ `red-r2-2/` を作る。`degraded` は `false` のまま

### A-1-F 失敗注入

各項目で新しいセッションを起動する。グローバル設定（installed_plugins.json 等）は触らない。

#### A-1-F-1 exit 2: companion 不在

- 起動: `cd "$SCRATCH" && CODEX_COMPANION_PATH=/nonexistent CODEX_COMPANION_NO_CACHE_FALLBACK=1 claude --plugin-dir "$REPO"`
- 依頼: `/codex-collab:strong-inference rotate-logs.sh が "rotated N file(s)" を出さずに非0終了することがある`
- 期待:
  - [ ] `hypothesis-r1-1/error.log` に `CODEX_COMPANION_PATH not found`、`answer.md` なし
  - [ ] 会話記録で、exit 2 の完了通知の**直後・次のツール呼び出しより前**に「⚠️ Codex を使えないため（`run-codex-role.sh` 終了コード 2: …）、hypothesis-r1 以降を Claude だけで続けます」の警告テキストがある（最終レポートの注記だけでは不合格）
  - [ ] claude-only で継続、state.md に `degraded: true`、`mode: claude-only`、`codex_call_failures` に `{role: hypothesis-r1, exit: 2, attempt: 1}`
  - [ ] 完了レポートの Confidence に「独立レビューなし（claude-only）」

#### A-1-F-2 exit 2: setup が `codex.available:false`

- 起動: 0-3 に `MOCK_SETUP_JSON='{"ready":false,"codex":{"available":false},"auth":{"loggedIn":true}}'` を追加
- 依頼: `/codex-collab:devils-advocate --max-rounds 2 config.yaml をリクエスト毎に読む実装をやめ、起動時に 1 回読み込み SIGHUP で再読み込みする`
- 期待:
  - [ ] 会話記録で、exit 2 の完了通知の**直後・次のツール呼び出し（サブエージェント起動を含む）より前**に「⚠️ Codex を使えないため（…）、red-r1 以降を Claude だけで続けます」の警告テキストがある（「Claude のサブエージェントに書かせています」だけでは不合格）
  - [ ] `red-r1-1/error.log` に `Codex not ready`、claude-only、`degraded: true`、`codex_call_failures` に `{role: red-r1, exit: 2, attempt: 1}`
  - [ ] 最終レポートで Red Team が Claude であり独立した外部批評ではないと明記

#### A-1-F-3 exit 2 × `--abduce` → blocked_no_codex

- 起動: A-1-F-2 と同じ（`MOCK_SETUP_JSON` 付き）
- 依頼: `/codex-collab:dialectic-loop --abduce --corpus "$REPO/tests/acceptance/fixtures/corpus/*.sh"`（絶対パスで）
- 期待:
  - [ ] `abduction-1/` が exit 2、state.md に `status: blocked_no_codex`、`codex_call_failures` に `{role: abduction, exit: 2, attempt: 1}`
  - [ ] claude-only に縮退しない（Claude が候補仮説を作らない）。retry / abort / default variant への切り替えをユーザーに尋ねて停止
  - [ ] 別途 `--abduce --mode claude-only` と `--abduce --rotate` は開始前にエラーになる（任意）

#### A-1-F-4 exit 5: 空 rawOutput

- 起動: 0-3 に `MOCK_RAW_OUTPUT=''` を追加
- 依頼: A-1-SI-1 と同じ strong-inference、または A-1-DA-1 の devils-advocate
- 期待:
  - [ ] `hypothesis-r1-1/`（または `red-r1-1/`）が exit 5、`error.log` に `empty rawOutput`、`answer.md` なし
  - [ ] 次相へ進まない: strong-inference は `## Hypotheses` が `(Pending generation)` のまま / devils-advocate は `round: 0` のまま
  - [ ] `codex_call_failures` に exit 5 を記録、`degraded: false`、自動再実行なし（`-2` の attempt なし）、ユーザーに判断を仰ぐ

### A-1-N-1 非漏洩（inputs.json 許可リスト）

A-1 のすべての task について実行する。

```bash
for d in "$BASE"/*/*/; do echo "== $d"; node "$REPO/tests/acceptance/check-inputs.mjs" "$d"; done
```

- contradiction-lift の preserve-b-* 行は匿名化キーに依存する。fixture（20001）と `anonymization_key: "X=A,Y=B"` の task は既定の `inputs-allowlist.json`、`"X=B,Y=A"` の task は `node "$REPO/tests/acceptance/check-inputs.mjs" "$d" "$REPO/tests/acceptance/fixtures/inputs-allowlist.x-is-b.json"`
- inputs.json が 1 つもない task（claude-only で完了したもの等）は `checked=0` で exit 1 になる。対象外としてメモする
- 期待:
  - [ ] Codex 呼び出しをした全 task で `failed=0`
  - [ ] 補助 grep（許可リストの `<N>` / `<N-1>` は任意の番号に一致するため、ラウンド相対の制約はここで目視確認する）:
    - devils-advocate `red-r3` 以降の inputs.json に `Debate Log/Round <N-2 以前>` がない
    - contradiction-lift `audit-r<n>` の inputs.json に `Lift/Attempt <n 以外>` / `Audit/*` がない
    - `grep -l "Sealed Solutions" "$BASE"/contradiction-lift/*/*/prompt.md` が 0 件
    - `grep -l -E "Candidate H[0-9]|### Candidates|### Selection" "$BASE"/dialectic-loop/*/induction-r*/prompt.md` が 0 件

### A-1-G-1 対象リポジトリ不変

- [ ] `git -C "$SCRATCH" status --porcelain | diff /tmp/gate-a-status-before.txt -` が差分なし
- [ ] `ls "$SCRATCH/tmp"` が存在しない

---

## A-2 実モデル完走（最小回数）

- 起動（mock の環境変数を**付けない**）: `cd "$SCRATCH" && claude --plugin-dir "$REPO"`
- 開始前に 0-1 の `git status --porcelain` 記録を取り直す。A-1 の state と区別するため、各 task の state dir をメモ欄に記録する
- 期待値（CLAUDE.md「利用量ポリシー」、step 7b）: 本体ロール = config.toml 既定（2026-09-16 時点 `gpt-6-astra` / `low`）、軽量ロール（Mapper）= `gpt-5.6-luna` / `low`。実施時に config.toml が変わっていれば、実施記録の値で `--expect` を書き換える

### 合否一覧

| ID | 項目 | 合否 | メモ |
|---|---|---|---|
| A-2-SI | strong-inference 1 回完走 + usage 合格 | 合格（所見あり） | state dir `strong-inference/20260916-084537-15958`。collect-usage は rows=2 failed=0（hypothesis-r1-1 / review-1 とも gpt-6-astra・low・read-only・turns 1・verbatim yes、input 17685 / 18246）。**所見（実モデルでのみ再現する競合）**: review-1 は 08:50:33 に exit 0 で DONE・answer.md 2255B・duration_sec 23 だったのに、完了通知を待たずに読んだため「空の結果」と誤判定し、`codex_call_failures` に exit 5 を記録してユーザーに質問した。事実を伝えて既存 answer.md の採用と誤記録の取り消しを指示し、完走させた（`codex_call_failures: []`、`review_thread_id` 記録済み）。mock は応答が即時のため A-1 では再現しない。1 回目の投入 2 件は mock 環境が残ったセッションに届いたため退避（`…-084135-22351-misfire2`、`…-083407-17907-misfire`）し、以後は起動後に `/proc/<pid>/environ` で MOCK 変数 0 件を確認してから実施 |
| A-2-CL | contradiction-lift 1 回完走（到達分岐は問わない）+ usage 合格 | 合格 | state dir `contradiction-lift/20260916-085343-4777`、到達先は `state: aporia` / `outcome: aporia`（`lift_attempts` 2、`empirical_arbiter: deferred`）。実モデルでは Lift が Claude subagent・Audit が Codex の cross-model 組み合わせになった（`lift_role: claude-subagent`、`audit_role: codex-thread`）ため、Lift は collect-usage の表に出ない。collect-usage は rows=8 failed=0（mapper のみ gpt-5.6-luna/low、他 7 件は gpt-6-astra/low、全件 read-only・turns 1・verbatim yes、input 17121〜23244）。非漏洩は `anonymization_key: "X=B,Y=A"` に合わせた x-is-b 許可リストで checked=8 failed=0 |
| A-2-DL | dialectic-loop `--abduce` 1 回完走 + usage 合格 | 合格 | state dir `dialectic-loop/20260916-092932-5760`。`status: completed`・`round: 2`、`abduction_thread_id`（`…533a46`）≠ `induction_thread_id`（`…d49dc0`）、Disk recompute 2 件、`evidence_scope: exploratory_in_sample`。collect-usage は rows=3 failed=0（全件 gpt-6-astra/low・read-only・turns 1・verbatim yes、input 77615 / 97282 / 81663 で上限 30 万内）。非漏洩 checked=3 failed=0 |
| A-2-G | 対象リポジトリの git status 不変 | 合格 | A-2 開始前に取り直した基準（空）と差分なし、`$SCRATCH/tmp` なし |
| A-2-U | `tests/acceptance/usage-report.md` に全呼び出しを記録 | 合格 | 3 手法の collect-usage 出力（計 13 行、failed=0）と実行環境を記録。上限超過・rollout 未検出の行なし |

### A-2-SI strong-inference

- 依頼: `/codex-collab:strong-inference rotate-logs.sh が "rotated N file(s)" を出さずに非0終了することがある`（題材は 0-1 で `$SCRATCH` にコピーした corpus）
- 完走後:

  ```bash
  node "$REPO/tests/acceptance/collect-usage.mjs" "<state-dir>" \
    --expect hypothesis=gpt-6-astra/low --expect review=gpt-6-astra/low
  ```

- [ ] `status` が完了（Investigation Complete のレポート）
- [ ] collect-usage が exit 0（全行: turns 1、sandbox `read-only`、verbatim yes、model / effort 一致、input ≤ 100000、rollout 未検出なし）

### A-2-CL contradiction-lift

- 依頼: `/codex-collab:contradiction-lift 設定値の検証を起動時に一括で行う（fail-fast）か、各機能の初回利用時に遅延して行う（lazy）か`（Decision Contract は A-1-CL-1 と同じ内容で合意）
- 完走後:

  ```bash
  node "$REPO/tests/acceptance/collect-usage.mjs" "<state-dir>" \
    --expect solver-b=gpt-6-astra/low --expect mapper=gpt-5.6-luna/low \
    --expect arbiter=gpt-6-astra/low --expect preserve-b=gpt-6-astra/low \
    --expect lift=gpt-6-astra/low --expect audit=gpt-6-astra/low
  ```

- [ ] `state` が `accepted` / `aporia` / `no_material_divergence` のいずれか（到達先をメモ）
- [ ] collect-usage が exit 0。Claude subagent が担ったロール（meta.json なし）は表に出ないので、どのロールが Codex だったかを state.md の actor key と照合してメモ
- [ ] A-1-N-1 のコマンドで非漏洩 `failed=0`（匿名化キーに合う許可リストで）

### A-2-DL dialectic-loop `--abduce`

- 依頼: `/codex-collab:dialectic-loop --abduce --corpus "$REPO/tests/acceptance/fixtures/corpus/*.sh" --max-rounds 2`（絶対パスで）
- 完走後:

  ```bash
  node "$REPO/tests/acceptance/collect-usage.mjs" "<state-dir>" \
    --limit abduction=300000 --limit induction=300000 \
    --expect abduction=gpt-6-astra/low --expect induction=gpt-6-astra/low \
    --expect deduction=gpt-6-astra/low
  ```

- [ ] `status: completed`、`abduction_thread_id` ≠ `induction_thread_id`、Disk recompute あり、`evidence_scope: exploratory_in_sample`
- [ ] collect-usage が exit 0（abduction / induction は入力上限 30 万、それ以外は 10 万）
- [ ] 非漏洩 `failed=0`

### A-2-G 対象リポジトリ不変

- [ ] `git -C "$SCRATCH" status --porcelain` が開始前の記録と同一、`$SCRATCH/tmp` なし

### A-2-U 利用量レポート

- [ ] 3 手法の collect-usage 出力を `tests/acceptance/usage-report.md` の各節に貼り、実行環境欄を埋める
- [ ] 上限超過・測定不能（rollout 未検出）の行があれば不合格とし、所見欄に対応を書く

---

## 補足

- **fixture の自己検証**（Claude セッション不要）: 各固定応答について、ロールマーカー 1 行目の prompt で `run-codex-role.sh` を mock 経由で実行し exit 0・`answer.md` == `rawOutput`・threadId 一致を確認済み。`states/` の inputs.json は `check-inputs.mjs` で `failed=0`、許可リストから作った合成 state は合格、漏洩させた inputs.json（solver-b に Sealed A、mapper に Sealed、preserve-b-review に相手解、induction に Abduction / original_claim）は不合格になることを確認済み
- **corpus**（`fixtures/corpus/*.sh`、6 ファイル）の実測値: `set -euo pipefail` 4/6、関数定義 16 件中 camelCase 2 件（sync.sh）、die 呼び出し 8 件、die 以外の直接 exit 2 件（cleanup.sh:11, sync.sh:17）。strict mode 宣言ファイルのエラー終了は 7/7 が die 経由、非宣言ファイルは 1/3。dialectic-loop の固定応答の数値はこの実測値と一致させてある（Arbitration の Disk recompute で食い違いが出ないように）
- **固定応答と Claude 側の出力は噛み合わないことがある**（例: induction の P 番号と Claude が導いた予測）。A-1 は分岐到達・role 分離・状態遷移を判定し、内容の妥当性は判定しない
