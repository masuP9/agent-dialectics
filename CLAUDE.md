# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイダンスを提供します。

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

## 4手法スキルの Codex 呼び出し

strong-inference / devils-advocate / dialectic-loop / contradiction-lift は `skills/<method>/SKILL.md` だけで完結し（`/codex-collab:<method>` で起動）、Codex 役は **`scripts/run-codex-role.sh` の 1 経路のみ**で呼ぶ。`codex exec` / `codex review` を直接叩く経路は v0.40.0 で廃止した。

- 中身は公式 codex-plugin-cc companion の `node codex-companion.mjs task --fresh --json --prompt-file … --cwd …`。事前に `setup --json` で `ready`・`codex.available`・`auth.loggedIn` を確認
- 成功条件: 終了コード 0 かつ JSON パース成功かつ `status === 0`（数値）かつ trim(rawOutput) 非空かつ touchedFiles 空。そのときだけ `answer.md`・`meta.json`・`DONE` を書く
- 終了コード: `0` 成功 / `1` 引数エラー・attempt ディレクトリ再利用 / `2` Codex 不可 / `4` 実行失敗 / `5` 結果不正。4・5 は自動再実行しない
- `--write` / `--resume` / `--resume-last` / `--background` は受け付けない（常に fresh・read-only）
- 作業ファイルは対象リポジトリの外: `${XDG_STATE_HOME:-~/.local/state}/agent-dialectics/<repo-slug>/<method>/<task-id>/`
- テスト用の差し替え: `CODEX_COMPANION_PATH`（companion のパス）、`INSTALLED_PLUGINS_JSON`、`CODEX_COMPANION_NO_CACHE_FALLBACK=1`。偽 companion は `tests/acceptance/mock-companion.mjs`

### 利用量ポリシー

- Codex 役は常に fresh。反復は state.md の要約と抜粋を貼った自己完結プロンプトで再投入する
- 事実（ファイル抜粋・行番号）はプロンプトに入れ、リポジトリ探索を指示しない（例外: dialectic-loop の abduction / induction は corpus 読取が役割）
- 1 呼び出しあたり入力 10 万トークンまで（例外ロールは各 SKILL.md のロール表で個別上限を宣言）
- ロール別モデル（ゲート A の期待値、2026-09-16 時点の `~/.codex/models_cache.json` から選定）:
  - 本体ロール（封印解・Lift・Audit・批評・検証）: `--model` / `--effort` を付けない = config.toml 既定（現在 `gpt-6-astra` / `low`）
  - 軽量ロール（Mapper・分類・単純確認）: `--model gpt-5.6-luna --effort low`
- Web 検索: codex-cli 0.154.0 では `--search` 指定時のみ有効になる。companion 経由で無効化する設定キーは未確認のため、全ロールのプロンプトで Web 検索を使わないよう明記している
- 手法の実行中・直後に同じリポジトリで `/codex:rescue --resume` を使わない（手法のロール thread を継続してしまう）

## プロジェクト構造

- `skills/` - Claude Code のスキル（4手法。`/codex-collab:<method>` で起動）
- `codex-skills/` - Codex CLI のスキル（`claude-collab`）。Claude Code はここをスキルとして読み込まない
- `scripts/` - `run-codex-role.sh`（Codex 役の唯一の呼び出し経路）と検査・テスト
- `tests/acceptance/` - 受け入れ試験（偽 companion・固定応答・チェックリスト）
- `.claude-plugin/plugin.json` - プラグインメタデータ（バージョン含む）
- `.claude-plugin/marketplace.json` - マーケットプレイス公開用メタデータ（バージョン含む）
- `.gitignore` - 一時ファイルの除外パターン

## スキルの使い分け

| 目的 | 使用するスキル |
|------|---------------|
| 未知の原因を究明（バグ/デバッグ） | `/codex-collab:strong-inference [problem]` |
| 設計案を反証でストレステスト | `/codex-collab:devils-advocate [proposal]` |
| 経験的主張をデータで検証・精緻化 | `/codex-collab:dialectic-loop [claim]` |
| 競合する2解を平均でなく止揚 | `/codex-collab:contradiction-lift [question]` |

> **strong-inference**=未知の原因、**devils-advocate**=1つの提案を外から叩く、**dialectic-loop**=主張×現物データ、**contradiction-lift**=独立した2解の食い違いを止揚。詳細な選択ガイドは README「スキルの使い分け」。

実装や計画そのものの委譲は、このプラグインの役目ではない（公式 codex-plugin-cc を使う）。

## テスト

PR 作成前に以下をすべて実行し、全テストがパスすることを確認すること。

```sh
bash codex-skills/claude-collab/scripts/test-claude-helpers.sh  # claude-collab ヘルパーのテスト
bash scripts/test-run-codex-role.sh                             # run-codex-role.sh のテスト（node 必須、偽 companion 使用）
bash scripts/lint-plugin.sh                                     # バージョン同期・SKILL.md frontmatter・相対リンク・禁止参照語（PyYAML 必須）
```

- 外部依存は bash / node / python3（PyYAML）のみ。実 codex 呼び出しはない
- CI（`.github/workflows/ci.yml`）でも同じスイートを実行している
- 4手法スキルの受け入れ確認は `tests/acceptance/checklist.md`（ゲート A）
- スクリプトを追加・変更した場合は対応するテストを追加すること
