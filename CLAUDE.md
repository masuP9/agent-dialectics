# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイダンスを提供します。

## masuP9 との会話で使う言葉

スキルの結果報告や設計の相談では、論理学・哲学・統計の専門用語をそのまま使わず、次の表の言い換えを使う(SKILL.md などの本文はそのままでよい)。

@docs/conversation-glossary.md

## Codex Leaf Reviewer Mode

Codex 側の `claude-collab` ラッパーから呼び出された場合、CLI の system prompt に `CLAUDE_COLLAB_CALLER=codex` 相当の leaf reviewer 指示が含まれます。

その場合:

- この `CLAUDE.md` はプロジェクト構造、リリースルール、実装上の制約を理解するために使用する
- Codex MCP、`codex exec`、`codex review`、Codex と一緒に作業するためのスキル、スラッシュコマンドを呼び出さない
- 新しく Codex と一緒に作業を始めず、既存セッションも継続しない
- ファイル変更、PR 作成、Bash 委任を行わない
- 依頼されたレビューまたは助言だけを返して終了する

## リリースワークフロー

### バージョン更新

PRを作成する前に、変更内容に応じて以下の **両方のファイル** のバージョンを更新すること。

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

**バージョニングルール:**

- **パッチ (0.0.x)**: バグ修正、ドキュメント修正、小さな改善
- **マイナー (0.x.0)**: 新機能追加、後方互換性のある変更
- **メジャー (x.0.0)**: 破壊的変更

```json
// plugin.json
{
  "version": "0.3.0"  // ← 変更内容に応じて更新
}

// marketplace.json (plugins[0].version も同じ値に更新)
{
  "plugins": [
    {
      "version": "0.3.0"  // ← plugin.json と同じ値
    }
  ]
}
```

## Codex 通信の仕様

OpenAI Codex と連携する際に知っておくべき仕様。通信は `codex` CLI のみ（検証済み: codex-cli 0.154.0 / 対応対象: 0.154.0 以上）。`codex mcp-server` は 0.154.0 で削除されたため使用しない。

### codex exec --json + codex exec resume（ステートフル実行）

`codex_run_exec_session()` が新規スレッドの作成と継続を統合処理する。

```sh
# 新規スレッド（stdout = JSONL イベント、-o = 最終メッセージ）
codex exec -s read-only --json -o out.md - < prompt.txt > out.jsonl 2> out.stderr.log

# 継続（-s は exec と resume の間。resume 自体に -s はない）
codex exec -s read-only resume <THREAD_UUID> --json -o out.md - < next.txt > out.jsonl 2> out.stderr.log
```

- thread id は `{"type":"thread.started","thread_id":"<uuid>"}` から取得し、セッション状態に保存する
- 応答本文は `-o` の出力ファイルのみを正とする（JSONL 本文のデコードはしない）
- `resume --last` / `--ephemeral` は使わない。UUID 以外を渡すと未知のスレッド名として**新規スレッドが黙って作られる**ため事前に拒否する
- 1 スレッド = 1 sandbox（claude-leads は Thread B = read-only、Thread C = workspace-write）
- 戻り値: `0` 成功（thread id を stdout）/ `2` 前提エラー（codex 未起動）/ `3` 再開対象スレッドなし（stderr `no rollout found for thread id <id>`、ターン未開始。**自動で 1 回だけ再構築可**）/ `4` 実行結果不明 / `5` 完了したが結果不正。`4`/`5` は自動再実行しない
- 呼び出しは `rc=0; X=$(codex_run_exec_session ...) || rc=$?` 形式（`set -e` 下でも分岐に到達させる）

### codex exec（ステートレス実行）

単発実行用。プロンプトを stdin から受け取り、結果を stdout に出力してブロッキング終了する。

```sh
# 基本パターン
codex exec -s read-only - < prompt.txt

# モデル指定（通常は省略して Codex デフォルトを使用）
codex exec -s read-only -m gpt-5.6-sol - < prompt.txt
```

- 各呼び出しはステートレス（会話コンテキストは保持されない）
- 出力に ANSI エスケープコードが含まれる場合があるため `codex_strip_ansi()` で除去
- `codex_run_exec()` がファイル入出力、ANSI 除去、exit code ハンドリングを統合処理

### codex review（コードレビュー）

`codex review --uncommitted` はステージ済み/未コミットの差分を自動収集してレビューを行う専用サブコマンド。`-s` / `-m` は受け付けないため `-c sandbox_mode=` / `-c model=` で指定する。

```sh
# 基本パターン
codex review --uncommitted

# カスタムプロンプト付き
codex review --uncommitted "セキュリティ脆弱性に注目してレビュー"
```

- レビューフェーズでは `codex review` を第一選択、失敗時は計画スレッドを `codex_run_exec_session` で resume してレビュー
- `codex_run_review()` が sandbox_mode 指定（既定 read-only、`-c sandbox_mode=` 経由）、ANSI 除去、出力保存、exit code ハンドリング、モデル指定 retry を統合処理
- `codex_infer_verdict()` でレスポンスから verdict を推定（メタデータ → `[P1]-[P4]` → findings なし pass）

## プロジェクト構造

- `commands/` - `/collab` などのスラッシュコマンド
- `scripts/` - 共通ヘルパースクリプト
- `skills/codex-collab/` - スキル定義とリファレンス
- `hooks/` - PreToolUse などのフック
- `docs/` - プラグインドキュメント（Bash使用ルールなど）
- `.claude-plugin/plugin.json` - プラグインメタデータ（バージョン含む）
- `.claude-plugin/marketplace.json` - マーケットプレイス公開用メタデータ（バージョン含む）
- `.gitignore` - Codex一時ファイルの除外パターン

## Bash 使用ルール

codex-collab のヘルパー関数を直接 Bash で実行すると、承認プロンプトが表示されることがあります。
**必ずスキル経由で実行してください。**

### クイックリファレンス

| 目的 | 使用するスキル |
|------|---------------|
| 協調タスク開始（計画〜実装〜レビュー） | `/codex-collab [task]` |
| 計画のみ作成 | `/collab-planning [idea]` |
| 未知の原因を究明（バグ/デバッグ） | `/strong-inference [problem]` |
| 設計案を反証でストレステスト | `/devils-advocate [proposal]` |
| 経験的主張をデータで検証・精緻化 | `/dialectic-loop [claim]` |
| 競合する2解を平均でなく止揚 | `/contradiction-lift [question]` |

> 分析系の使い分け: **strong-inference**=未知の原因、**devils-advocate**=1つの提案を外から叩く、**dialectic-loop**=主張×現物データ、**contradiction-lift**=独立した2解の食い違いを止揚。詳細な選択ガイドは README「スキルの使い分け」。

### 詳細ドキュメント

Bash 使用ルールの詳細（スキルコンテキスト検出の仕組み、検出パターン、制限事項、トラブルシューティング）については、以下を参照してください:

**→ [docs/bash-usage.md](docs/bash-usage.md)**

> **Note**: `hooks/enforce-skill-usage.sh` の PreToolUse フック（command型）がこのルールを強制します。
> 新しいコマンドを作成する場合は、`export CODEX_SKILL_CONTEXT=1` を Bash ブロックの先頭に追加してください。

## テスト

PR 作成前に以下の両方を実行し、全テストがパスすることを確認すること。

```sh
bash scripts/test-helpers.sh                              # ヘルパー関数のユニットテスト
bash skills/claude-collab/scripts/test-claude-helpers.sh  # claude-collab ヘルパーのテスト
```

- 純粋な bash のみで動作し、外部依存・実 codex 呼び出しはない
- CI（`.github/workflows/ci.yml`）でも同じ 2 スイートを実行している
- ヘルパー関数を追加・変更した場合は対応するテストを追加すること

## ヘルパースクリプトの管理

`scripts/codex-helpers.sh` には、コマンド間で共有されるbash関数が定義されています。

### 使用方法

各コマンドのbashブロックで以下のようにsourceします:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1

# Robust helper loading with fallback chain
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
[ -z "$HELPERS" ] || [ ! -f "$HELPERS" ] && HELPERS="$(pwd)/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"
```

> **注意:** `${CLAUDE_PLUGIN_ROOT}` はClaude Codeのコマンドmarkdown内では動作しない既知のバグがあります（[#9354](https://github.com/anthropics/claude-code/issues/9354)）。上記のフォールバックチェーンで `~/.claude/plugins/cache` を探索するようにしています。

### 関数の追加・変更

新しい共通関数を追加する場合:

1. `scripts/codex-helpers.sh` に関数を追加
2. 関数名は `codex_` プレフィックスを使用（例: `codex_new_function()`）

### 現在の関数一覧

コア関数（Codex 実行）:

- `codex_run_exec_session()` - `codex exec --json` / `codex exec resume` のラッパー（thread id を stdout に返す。戻り値 0/2/3/4/5 で失敗を分類、JSONL/stderr を出力ファイル隣に分離保存）
- `codex_extract_thread_id()` - JSONL の `thread.started` 行（行頭アンカー）から UUID を 1 つだけ抽出
- `codex_is_valid_uuid()` / `codex_is_valid_sandbox()` - thread id（8-4-4-4-12）/ sandbox 値の検証
- `codex_run_exec()` - codex exec のステートレス実行ラッパー（stdin パイプ、ANSI 除去、出力保存、exit code ハンドリング）
- `codex_run_review()` - codex review --uncommitted のラッパー（sandbox_mode 指定、ANSI 除去、出力保存、モデル retry、exit code ハンドリング）
- `codex_build_exec_command()` - codex exec コマンド文字列の構築
- `codex_write_prompt()` - プロンプトを一時ファイルに書き出し
- `codex_strip_ansi()` - ANSI エスケープコード除去

レビュー解析:

- `codex_infer_verdict()` - レビューレスポンスから verdict を推定（メタデータ → [P1]-[P4] → findings なし pass）
- `codex_extract_review_findings()` - レビューレスポンスから findings を抽出

セッション状態管理（exec スレッド用）:

- `codex_save_session_state()` - セッション状態を JSON ファイルに保存（task_id 単位で分離、値はエスケープ済み。mode は `exec`）
- `codex_load_session_state()` - セッション状態を読み込み（MODE, THREAD_ID 等をグローバル変数にセット。戻り値 0 / 1 未検出 / 2 移行・I/O 失敗）
- `codex_save_thread()` - 名前付きスレッドの生の値を保存
- `codex_save_thread_session()` - 名前付きスレッドを `uuid|sandbox` 形式で検証して保存（claude-leads の Thread B/C 用）
- `codex_load_session_thread()` - メインスレッド（Thread A 等）を指定 sandbox で再開できるか判定し UUID を返す（戻り値 0 再開可 / 1 なし・旧形式・不正値・sandbox 不一致 → 新規スレッド / 2 I/O 失敗 → 停止）
- `codex_load_thread()` / `codex_load_thread_sandbox()` - 名前付きスレッドの UUID / sandbox を読み込み（戻り値 0 / 1 なし・旧形式・不正値 → 新規スレッド / 2 I/O 失敗 → 停止）
- 旧形式（mode `mcp`/`bash`）の状態ファイルは load/save 系の入口で自動移行（threadId/threads を破棄、tmp+mv で置換）。同一 task の状態書き込みはオーケストレーターが直列に行う
- load 系も移行で書き込むため、PreToolUse フックのガード対象に含まれる
- `codex_sanitize_task_id()` - task_id のファイル名安全化（英数字・ハイフン・アンダースコアのみ）
- `codex_json_escape()` - JSON 値のエスケープ（引用符・バックスラッシュ・改行）
- `codex_diff_tier()` - diff のサイズに応じてティア判定（small/medium/large）

ユーティリティ関数:

- `codex_ensure_tmp_dir()` - 一時ディレクトリの確保（絶対パスを返す）
- `codex_tmp_path()` - 一時ディレクトリ内のファイルパス取得
- `codex_hash_content()` - クロスプラットフォームハッシュ計算
- `codex_generate_signal()` - ユニークID生成
- `codex_get_language_directive()` - 言語指示生成（多言語対応）
- `codex_debug()` - デバッグログ出力

メタデータ抽出:

- `codex_extract_metadata()` - レスポンスからメタデータ抽出
- `codex_get_field()` - メタデータフィールド取得
- `codex_get_status()` / `codex_get_verdict()` - メタデータフィールド取得
