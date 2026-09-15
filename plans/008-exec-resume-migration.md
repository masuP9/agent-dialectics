# Plan 008: MCP 経路を廃止し `codex exec` + `exec resume` を唯一の通信経路にする

> **Executor instructions**: 5. Implementation Steps の順に実行する。最初の
> ゲート試験 (5.1) の結果が 3.1 / 3.3 の前提と矛盾する場合は STOP して報告する。
> 完了時に `plans/README.md` の本プランの行を更新する。

## Status

- **Priority**: P1（codex-cli 0.154.0 で `codex mcp-server` が削除され MCP primary 経路が常に失敗）
- **Effort**: L
- **Risk**: MEDIUM（全コマンドの通信経路を置換。自動再実行は rc=3 のみに限定）
- **Depends on**: —
- **Origin**: 2026-09-15 `/collab-planning`（Codex レビュー 3 往復、最終指摘反映済み）


### 1. Purpose
codex-cli 0.154.0 で `codex mcp-server` が削除され、プラグインの「MCP primary」経路が常に失敗する。MCP 経路を撤去し、`codex exec --json` で得た `thread_id` を session state に保存、2 ターン目以降を `codex exec resume <thread_id>` で継続することで、MCP 時代と同等のステートフル multi-turn を Bash のみで実現する。失敗時の復旧条件を安全側に限定し、ドキュメント・フック・テストを実態に合わせる。

### 2. Scope Exclusions
- `codex app-server`（JSON-RPC）対応、自前 MCP アダプターの作成。
- MCP 経路の互換維持（コードは完全削除）。
- **検証済みは codex-cli 0.154.0、対応対象は 0.154.0 以上**。それ未満は保証対象外（README に明記。バージョン検出コードは入れない）。
- ユーザーの `~/.mcp.json` 等の個人設定の書き換え（README で削除を案内するのみ）。
- `skills/claude-collab/`（Codex→Claude 方向）の変更。
- `plans/**`, `docs/plans/**` の過去計画ドキュメントの書き換え。
- `codex_run_review`（`codex review --uncommitted`）のロジック変更。
- JSONL 本文（agent_message テキスト）の JSON デコード。本文は `-o` 出力のみを正とする。
- ワークフロー/プロンプトの観点内容自体の変更。

### 3. Design Contracts（実装前に確定する契約）

**3.1 `codex_run_exec_session PROMPT OUTPUT SANDBOX MODEL [THREAD_ID]`**
- 呼び出し前に `OUTPUT`, `OUTPUT%.md.jsonl`, `OUTPUT%.md.stderr.log` を削除（古い出力の誤用防止）。
- 新規: `codex exec -s S [-m M] --json -o OUTPUT - < PROMPT > JSONL 2> STDERR`
- 継続: `codex exec -s S [-m M] resume THREAD_ID --json -o OUTPUT - < PROMPT > JSONL 2> STDERR`（`-s` は exec と resume の間。`-c sandbox_mode` を追加するかは 5.1 のゲート試験結果で決定）
- `--last` と `--ephemeral` は使用しない。
- 返却: 成功時のみ stdout に thread_id を 1 行。グローバル変数は使わない。`exit` ではなく `return`。
- 呼び出し雛形（`set -e` 下でも分岐に到達する形に統一）:
  ```bash
  rc=0
  THREAD_ID=$(codex_run_exec_session "$PROMPT" "$OUT" "$SANDBOX" "$MODEL" "$PREV_THREAD_ID") || rc=$?
  ```
- 終了コード（**以下の優先順位で判定**）:
  1. `2` 前提・ローカル I/O エラー — prompt 不在、codex 不在、THREAD_ID が UUID `8-4-4-4-12` 形式でない、sandbox 値不正、PROMPT と出力パスの衝突、旧出力の削除失敗、JSONL/STDERR ファイル作成失敗。**codex 起動前に検出**し、codex は実行しない。
  2. `3` **肯定的に識別できた再開前の拒否**（継続時のみ）— codex 非0 **かつ** JSONL が 0 バイト **かつ** STDERR に `no rollout found for thread id <指定THREAD_ID>` を含む（0.154.0 で実測: exit 1, JSONL 0 行, -o 未作成, `thread/resume failed: no rollout found for thread id … (code -32600)`）。**自動復旧可の唯一のケース**。
  3. `4` 実行有無・完了が不明 — 上記以外の codex 非0、JSONL 欠損/破損、`turn.completed` 無し、未知のエラー文言。**自動復旧不可**。
  4. `5` 正常完了だが結果不正 — codex 0 かつ `turn.completed` ありだが、OUTPUT 空/未作成、thread_id 取得不可、thread.started の ID が複数で競合、（継続時）ID が指定と不一致。**自動復旧不可**。
  5. `0` 成功 — codex 0、`turn.completed` あり、OUTPUT 非空、有効な thread_id が一意に得られ（継続時は指定と一致）。
- **JSONL 構造検証（パーサー非依存、jq/python 不要）**: 0.154.0 実測のイベント行形式 `{"type":"<event>",...}`（type が先頭キー）に依拠する。
  - 全非空行が `^\{"type":"[a-z_.]+"` で始まり `\}$` で終わること。1 行でも外れれば「破損」→ rc=4。
  - `turn.completed` 判定は行頭アンカー `^\{"type":"turn\.completed"` のみ（行内の任意位置一致は採用しない）。
  - thread_id 抽出 `codex_extract_thread_id JSONL`: 行頭アンカー `^\{"type":"thread\.started","thread_id":"(UUID)"` からのみ、UUID `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}` を取得。0 件→空、異なる値が複数→空（いずれも return 非0 → 呼び出し側で rc=5）。
  - キー順序やイベント名が将来変わった場合は rc=4/5 に倒れる（自動再実行なし＝安全側）。本文（agent_message）の復号はしない。

**3.2 呼び出し側の復旧ルール（全コマンド共通）**
- rc=3 のみ: そのロール固有の入力（元タスク・現在の計画/仮説・直近のやり取り要約を state file から）で履歴再構築プロンプトを作り、**新規セッションで 1 回だけ**再実行、新 thread_id を保存。再失敗はユーザーに報告。
- rc=4/5: 自動再実行しない。stderr ログと JSONL 末尾を提示。workspace-write（claude-leads Thread C）では `git status`/`git diff --stat` を必ず確認してからユーザーに再試行/破棄/手動継続を AskUserQuestion。
- rc=2: エラー報告して停止（Codex 不在時は既存の claude-only 分岐へ）。

**3.2b 状態読み取り結果の分類（resume 実行前）**
- `codex_load_thread` / `codex_load_thread_sandbox` / `codex_load_session_state` の return:
  - `0` 有効な継続先あり（UUID/sandbox を stdout）
  - `1` 継続先なし（未保存）または旧形式/不正値で無効化済み → 呼び出し側は**保存済みロール入力から新規セッションを作成**（resume はしない。rc=3 経路とは別の「実行前復旧」）
  - `2` 移行・読み取り I/O 失敗 → **停止**してユーザーに報告（新規作成で救済しない）
- 呼び出し雛形も `rc=0; X=$(codex_load_thread ...) || rc=$?` 形式。

**3.2c 並行性**
- 同一 task_id の state 読み書き（移行・save_session_state・save_thread）は**オーケストレーター（Claude のメインループ）が直列に行う**。並行ロール（contradiction-lift 等）は Codex 実行自体は並行可だが、state への書き戻しは直列化する旨を各コマンドに明記。ロックは導入しない（スコープ外）。tmp+mv は部分書き込み露出の防止のみを目的とする。

**3.3 sandbox ポリシー**
- 1 スレッド = 1 sandbox。同一スレッドで sandbox を変えない（claude-leads は Thread B=read-only / Thread C=workspace-write を別スレッドで維持）。
- session state の named thread に sandbox も保存し、ヘルパー呼び出し側は保存 sandbox と一致する場合のみ resume。

**3.4 session state 移行**
- mode 値: 新規保存は `exec`。
- 移行処理は内部関数 `_codex_migrate_session_state STATE_FILE` に集約し、**`codex_load_session_state` と `codex_load_thread`（および sandbox 取得関数）の全読み取り入口で最初に呼ぶ**。
  - `mode` が `mcp` → mode=exec, threadId="", threads={} に書き換え。`bash` → mode=exec に正規化（threadId は保持しない＝空）。
  - 書き込みは同ディレクトリの一時ファイルへ出力後 `mv` で置換。失敗時は旧 ID を一切返さず非0 return（呼び出し側は rc=2 相当で停止）。
- これにより load 系関数は書き込み副作用を持つ → `hooks/enforce-skill-usage.sh` のガード対象に `load_session_state` / `load_thread` を追加する（ガード方針「状態を書き込むヘルパー」と整合）。docs/bash-usage.md にも明記。
- 再保存時に旧 `threads` が引き継がれないことをテストで保証。
- named thread の保存形式:
  - 保存 API は既存どおり `codex_save_thread TASK_ID NAME VALUE`。VALUE は JSON 文字列型のまま `"<uuid>|<sandbox>"`（`|` は既存 sed/JSON エスケープ処理を壊さないことを Codex がコード確認済み）。
  - 新規ラッパー `codex_save_thread_session TASK_ID NAME UUID SANDBOX` が検証（UUID 形式・sandbox ∈ {read-only, workspace-write, danger-full-access}）してから `UUID|SANDBOX` を保存。
  - `codex_load_thread TASK_ID NAME` は **UUID のみ**返す。`codex_load_thread_sandbox TASK_ID NAME` は sandbox のみ返す。両者は同一の分割・検証関数を共有。
  - 区切り無し（旧形式の生 ID を含む）、区切り過多、UUID/sandbox 不正 → 空を返し非0（推測で resume しない → 呼び出し側は新規スレッド作成）。
- contradiction-lift / dialectic-loop の markdown state:
  - **ロール単位**で backend を記録する: `<role>_thread_id: "exec:<uuid>"` 形式（contradiction-lift: solver_b/mapper/lift/audit、dialectic-loop: induction）。
  - `exec:` 接頭辞のない既存値（旧 MCP threadId、`bash-exec-*`、`claude-subagent-*` 以外）は resume 不可として扱い、そのロールのみ 3.2 の再構築で新規スレッドを作る。
  - `bash-exec-*` センチネルは**旧 state の識別用に限定**し、新規実行では使わない（thread_id 取得失敗は rc=5 として扱う）。`claude-subagent-*` は Claude サブエージェント役の actor key として従来どおり。

### 4. Work Breakdown (WBS)
| # | File | Action | Description |
|---|------|--------|-------------|
| 1 | scripts/codex-helpers.sh | modify | 3.1 の `codex_run_exec_session` / `codex_extract_thread_id` を追加。`codex_run_exec` はステートレス用途で残す。 |
| 2 | scripts/codex-helpers.sh | modify | 3.4: `_codex_migrate_session_state`（一時ファイル+mv）を全読み取り入口で呼ぶ、`codex_save_thread_session`、`codex_load_thread`（UUID のみ返す）、`codex_load_thread_sandbox`、共通の分割・検証関数。 |
| 3 | scripts/test-helpers.sh | modify | mode=mcp 前提テストを移行テストに書き換え。mock codex（PATH 差し替え、argv 記録、シナリオ別に JSONL/STDERR/-o/exit を制御）で: 新規 argv、resume argv 順序、stdout/stderr 分離、**rc 優先順位の各ケース**（2: prompt 不在/不正 UUID/出力パス衝突/削除不可 — codex が呼ばれないこと、3: 非0+JSONL 空+`no rollout found for thread id <ID>`、3 にならない: 別 ID の文言/JSONL 非空/exit 0、4: 非0+turn.started のみ・JSONL 破損・JSONL 空だが未知文言・非0+turn.completed+OUTPUT 空（複合失敗）、5: exit0+turn.completed+OUTPUT 空・ID 不一致・競合 ID 複数、0: 正常）、事前の古い OUTPUT 削除、UUID 8-4-4-4-12 検証、日本語/引用符/バックスラッシュ/改行を含む OUTPUT の保持、legacy mode=mcp/bash のファイル移行（`codex_load_thread` を先に呼んでも移行されること）、移行書き込み失敗時に旧 ID を返さないこと、再保存で旧 threads が復活しないこと、named thread の往復（B/C 保存 → B 更新 → session 再保存 → 両方の UUID/sandbox 読み取り）、区切り無し/過多/不正 sandbox で空+非0。 |
| 4 | hooks/enforce-skill-usage.sh | modify | PATTERN に `run_exec_session`, `save_thread_session`, `load_session_state`, `load_thread`, `load_thread_sandbox`（load 系は移行で書き込むため）を明示追加（`\b` 境界のため `run_exec`→`run_exec_session`、`load_thread`→`load_thread_sandbox` はそれぞれ一致しない）。メッセージの関数列挙も更新。 |
| 5 | hooks/test-enforce-skill-usage.sh | modify | 追加した 5 関数それぞれの直接呼び出し拒否、`CODEX_SKILL_CONTEXT=1` 付き許可、純粋関数（`codex_extract_thread_id` 等）が誤検知されないことを追加。 |
| 6 | hooks/enforce-skill-usage.md, docs/bash-usage.md | modify | ガード対象関数一覧に新ヘルパーを追加、MCP 記述があれば削除。 |
| 7 | commands/codex-collab.md | modify | Step 0a の MCP probe 削除（codex 存在確認のみ）。Step 3/5a/7(fallback)/8、claude-leads 4c/7c/9c、Compact Recovery の MCP Path を削除し、3.1/3.2/3.3 に従う呼び出し例に置換（3.1 の `rc=0; THREAD_ID=$(codex_run_exec_session ...) || rc=$?` 雛形、および 3.2b の load 雛形）。レビュー primary は `codex_run_review` のまま、その fallback exec と re-review の fallback を plan thread の resume に。exchange.history_mode は rc=3 再構築専用と明記。allowed-tools から mcp__codex__* 削除。 |
| 8 | commands/collab-planning.md | modify | Step 1b MCP probe 削除、Step 4 を exec_session（iter1）/ resume（iter2+、改訂差分とスナップショットのみ送信）に。rc=3 再構築入力 = task + 現ドラフト + Snapshot History。allowed-tools 更新。 |
| 9 | commands/strong-inference.md | modify | Step 3 exec_session、Step 7 resume。rc=3 再構築入力 = 問題記述 + 仮説一覧 + 検証結果。allowed-tools 更新。 |
| 10 | commands/devils-advocate.md | modify | Round 1 exec_session、Round 2+ resume。rc=3 再構築入力 = 提案 + 過去ラウンドの主張/反論要約。allowed-tools 更新。 |
| 11 | commands/dialectic-loop.md | modify | abduction は単発 exec_session、`induction_thread_id` を `exec:<uuid>` 形式に（round 2+ resume）。旧値（接頭辞なし）は 3.4 に従い再構築。「Bash は thread id なし」記述を修正。rc=3 再構築入力 = claim + 現仮説/予測 + 前ラウンド判定。allowed-tools 更新。 |
| 12 | commands/contradiction-lift.md | modify | solver_b / mapper / lift / audit を各々独立の新規スレッドで作成（resume は同一ロールの継続のみ）。actor key を `exec:<uuid>` 形式にしロール単位で backend を判別（3.4）。`bash-exec-*` は旧 state 識別専用に限定、新規では使わない。rc=3 再構築入力 = そのロールに渡した匿名化入力のみ（独立性維持）。allowed-tools 更新。 |
| 13 | skills/codex-collab/SKILL.md | modify | 通信方式を exec/resume に書き換え、MCP 記述削除、失敗分類の要約を記載。 |
| 14 | skills/contradiction-lift/SKILL.md, skills/dialectic-loop/SKILL.md, skills/dialectic-loop/references/induction-verification-template.md | modify | MCP 参照を exec/resume に置換、state テンプレートの `*_thread_id` を `exec:<uuid>` 形式の説明に更新。 |
| 15 | skills/codex-collab/references/codex-options.md | modify | MCP ツール節を削除し「`codex exec --json` / `exec resume`（引数順・-o・JSONL イベント）/ mcp-server 削除の経緯 (0.154.0)」節を追加。`codex review` は -s/-m 不可で -c を使う旨を明記。 |
| 16 | README.md | modify | 単一経路の説明、要件を「検証済み: codex-cli 0.154.0 / 対応対象: 0.154.0 以上」に、MCP サーバー設定を削除、既存ユーザー向け移行（`~/.mcp.json` の codex エントリ削除、旧 tmp state は自動移行）を追記。 |
| 17 | CLAUDE.md | modify | 「Codex 通信の仕様」節の書き換え、関数一覧に新関数追加・MCP 記述削除。 |
| 18 | .claude/codex-collab.local.md.example | modify | 「MCP モードでは無視」コメント修正（history_mode = rc=3 再構築用）。 |
| 19 | .claude-plugin/plugin.json, .claude-plugin/marketplace.json | modify | 0.37.3 → 0.38.0。 |

### 5. Implementation Steps (reference only — NOT executed by this skill)
1. **ゲート試験（全面移行前、実 codex）**: 使い捨て git リポジトリで、判定はモデルの返答でなく**ファイル実在と JSONL のツール結果**で行う。
   a. 新規 read-only → resume（read-only）で文脈保持。
   b. 新規 workspace-write → 同スレッドを `-s read-only` で resume し書き込み指示 → ファイルが作られないか。
   c. 新規 read-only → 同スレッドを `-s workspace-write` で resume し書き込み指示 → ファイルが作られるか。
   d. b/c で CLI 指定が効かなければ `-c sandbox_mode="S"` 併用で再試験。いずれにせよ 3.3（スレッド内 sandbox 固定）は維持。結果を codex-options.md に記録。
   e. rc=3 シグネチャの再確認（計画時点で 1 例実測済み: 無効 UUID → exit 1 / JSONL 0 行 / -o 未作成 / stderr `no rollout found for thread id <ID>`）。加えて、アーカイブ済み・削除済み（`codex delete`）スレッドの resume 挙動を収集し、同シグネチャ以外は rc=4 のままとする。
   f. `--json` と `-o` 併用で OUTPUT に最終メッセージ（メタデータブロック含む）が書かれること。
2. ゲート結果で 3.1 を確定し、WBS 1-3 をテスト先行で実装。
3. WBS 4-6（フック）。
4. WBS 7（codex-collab.md）を雛形として書き換え、続けて WBS 8-12。コマンド bash 内で新たに `$1`/`$2` 位置引数や awk フィールド参照を書かない（既知の置換バグ回避）。
5. WBS 13-18（ドキュメント）。
6. 残存参照チェック（7 の grep）。
7. バージョン更新、7 の検証を実行。

### 6. Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| resume 失敗時の再実行で副作用（Thread C のファイル変更）が二重適用 | High | 3.2: 自動再実行は rc=3（turn 未開始）のみ・1 回。rc=4/5 は git 状態確認のうえユーザー判断。 |
| resume で CLI の sandbox 指定が効かず、元セッション設定が優先（または逆）| High | ゲート試験 1b/1c/1d をファイル実在で判定。スレッド内 sandbox 固定ポリシー（3.3）でどちらでも安全に。 |
| 旧 state（mode=mcp / threads / markdown state の actor key）の無効 ID を resume | Medium | 3.4 のファイル移行、markdown state はロールごとに `exec:` 接頭辞が無ければ非継続扱い（3.2b の return 1 → 新規作成）。万一 resume しても rc=3 → 再構築。 |
| 同一 task の state 更新競合（移行と B/C 保存の重なり）で更新喪失 | Medium | 3.2c: オーケストレーターによる直列書き込みを各コマンドに明記。ロックはスコープ外。 |
| JSONL 検証がキー順序（type 先頭）に依存 | Low | 0.154.0 実測に基づく。順序変更時は rc=4/5 に倒れ自動再実行しない。ゲート 5.1 で再確認し codex-options.md に記録。 |
| 古い OUTPUT/JSONL の誤用で成功誤認 | Medium | 呼び出し前削除 + 成功条件に turn.completed と非空 OUTPUT。テストあり。 |
| JSONL スキーマ変更（thread.started / turn.* 名称）やエラー文言変更で判定崩壊 | Medium | 判定文字列を関数内定数に集約、mock テスト、codex-options.md に検証バージョン明記。rc=3 は肯定シグネチャ一致時のみなので、変更時は rc=4/5 に倒れ自動再実行しない（安全側）。 |
| load 系関数の書き込み副作用（移行）で競合・破損 | Low | 一時ファイル + mv、失敗時は旧 ID を返さず停止、フックのガード対象化。 |
| `-o` 未作成・空 | Medium | rc=5 として報告（JSONL デコードによる救済はしない＝スコープ外）。ゲート 1f で確認。 |
| stdout/サブシェルでの返却値消失・古い値残存 | Medium | 返却は stdout の thread_id のみ、グローバル変数不使用、`return` 使用。 |
| フック未更新で新ヘルパーが無防備 or スキル内で誤ブロック | Medium | WBS 4-6 必須化とテスト。 |
| 並行ロールでの誤スレッド選択/同時 resume | Medium | `--last` 禁止、ID 明示、同一スレッドは直列（ドキュメント明記）。 |
| コマンド markdown 大規模書き換えによる手順欠落・位置引数置換バグ | Medium | 雛形共通化、6 コマンドのスモーク行列（7 参照）。 |
| 0.154.0 未満ユーザーの破損 | Low | 保証対象外を README に明記。 |

### 7. Verification Methods
自動（CI と同一コマンド）:
- [ ] `bash scripts/test-helpers.sh`
- [ ] `bash skills/claude-collab/scripts/test-claude-helpers.sh`
- [ ] `bash hooks/test-enforce-skill-usage.sh`
- [ ] `shellcheck --source-path=SCRIPTDIR -x scripts/*.sh hooks/*.sh skills/claude-collab/scripts/*.sh`
- [ ] `.github/workflows/ci.yml` の JSON/YAML/frontmatter lint ステップ相当（pyyaml による検証スクリプト）
- [ ] `bash scripts/lint-plugin.sh`（バージョン整合含む）

手動ゲート: 5.1 の a〜f 全項目。

コマンド別スモーク行列（各: 新規 / 継続（同一 thread_id を state で確認）/ 復旧（state の `exec:` 接頭辞と `|sandbox` を保持したまま、UUID 部分だけを**形式上有効だが存在しない UUID** に書き換え → rc=3 → 再構築で新 thread_id 保存）/ 実行前復旧（値を形式不正にする → load return 1 → resume せず新規作成）/ 停止（state ファイルを書き込み不可にして旧形式を置く → load return 2 → 停止））:
- [ ] /codex-collab（codex-leads: 計画→exchange→実装→レビュー）
- [ ] /codex-collab（claude-leads: Thread B(ro) と Thread C(ws) が別 thread_id・別 sandbox で保存されること）
- [ ] /collab-planning
- [ ] /strong-inference
- [ ] /devils-advocate
- [ ] /dialectic-loop
- [ ] /contradiction-lift（各ロールの thread_id が互いに異なること、`exec:<uuid>` 形式で記録、旧形式 actor key 混在 state からロール単位で再構築されること）
- [ ] 旧 state 移行: mode=mcp + threads 入り state を置いて /codex-collab の Compact Recovery を実行 → 移行され新規スレッドで継続

残存参照 grep:
- [ ] `git grep -nE 'mcp__codex|codex mcp-server|codex-reply|MCP primary|MCP mode' -- . ':!plans/**' ':!docs/plans/**'` の結果が、(a) codex-options.md と README の「削除の経緯/移行」節、(b) test-helpers.sh の legacy mode=mcp 移行テスト、(c) helpers の移行コードのみ

### 8. Completion Criteria
- [ ] 7 の残存参照 grep が許容リスト (a)(b)(c) のみ
- [ ] 全 6 コマンド（codex-collab は 2 workflow）の multi-turn が `exec resume` で継続し、thread_id（と named thread の sandbox）が state に保存される
- [ ] **実行した resume の自動再試行は rc=3 のときのみ 1 回**。rc=4/5 では自動再実行されずユーザーに提示される
- [ ] 実行前の状態読み取りで継続先なし/無効（return 1）なら resume せず保存済み入力から新規作成、I/O 失敗（return 2）なら停止する
- [ ] 破損 JSONL（行頭形式不一致、破損行内に turn.completed/UUID を含むケース含む）が rc=4 になる（テストあり）
- [ ] 同一スレッド内で sandbox が変わらない
- [ ] 旧 state（mode=mcp）が読み込み時に移行され、旧 threadId/threads が使われない
- [ ] 7 の自動検証がすべてパス
- [ ] ゲート試験結果（sandbox 優先順位、無効 ID 時のイベント）が codex-options.md に記録
- [ ] plugin.json / marketplace.json が 0.38.0 で一致
- [ ] README に「0.154.0 以降のみサポート」と既存ユーザー移行手順がある
