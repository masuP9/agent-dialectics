# codex-collab

Claude Code と OpenAI Codex に**別々のモデルとして同じ問題を考えさせる**ための、4つの思考手法プラグイン。

Claude Code 側は 4手法スキル（strong-inference / devils-advocate / dialectic-loop / contradiction-lift）を提供し、Codex 側には Claude Code を read-only の相談役として呼び出す `claude-collab` スキルを提供します。

## 概要

同じモデルに考え直させても、同じ偏りが返ってきます。この 4手法は、Claude と Codex という**独立した 2つのモデル**に別々の役を割り当てて、片方だけでは出てこない指摘・反証・食い違いを取り出すためのものです。

| 手法 | 何をするか |
|------|-----------|
| strong-inference | 競合する仮説を立て、排除実験で未知の原因を絞り込む |
| devils-advocate | 1つの提案に反対役を当て、反証でストレステストする |
| dialectic-loop | 経験的な主張を現物データで確かめ、仮説を更新する |
| contradiction-lift | 独立に解いた 2つの答えの食い違いを、平均でなく一段上で統合する |

## インストール

### Claude Code から使う

```bash
# マーケットプレイスを追加
/plugin marketplace add https://github.com/masuP9/codex-collab

# プラグインをインストール
/plugin install codex-collab@codex-collab
```

### Codex から使う

Codex のスキルディレクトリへシンボリックリンクを作成します。

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -sfn "$(pwd)/codex-skills/claude-collab" "${CODEX_HOME:-$HOME/.codex}/skills/claude-collab"
```

`claude-collab` は Codex 専用なので `codex-skills/` に置いています。Claude Code はこのディレクトリをスキルとして読み込まないため、Claude 側のスキル一覧には出てきません。

Codex で「Claude と一緒に実装して」「Claude にレビューしてもらって」のように依頼すると、`claude-collab` スキルが Claude Code CLI を read-only の相談役として呼び出します。

## 前提条件

- OpenAI Codex CLI (`codex`) がインストール済みで、ログイン済みであること
  - **検証済み: codex-cli 0.154.0 / 対応対象: 0.154.0 以上**（それ未満は保証対象外）
- 公式プラグイン [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) がインストール済みであること（4手法の Codex 役はこの companion を経由して呼びます）
- Codex から `claude-collab` を使う場合は Claude Code CLI (`claude`) がインストール済みであること

### 以前のバージョンから移行する場合（v0.39 以前）

<!-- lint:legacy-history start -->
- v0.38.0 で `codex mcp-server` 経路を廃止しました。MCP 設定（例: `~/.mcp.json` や `~/.claude.json` の `mcpServers.codex`）に `codex mcp-server` が残っていると Claude Code 起動時に接続エラーになるので、そのエントリを削除してください。
- v0.40.0 で `/codex-collab`・`/collab-planning` コマンドと共通ヘルパー・PreToolUse フックを削除しました。実装や計画の委譲は公式 codex-plugin-cc をお使いください。
- v0.40.0 で `.claude/codex-collab.local.md` による設定を廃止しました。応答の言語は各スキルがプロンプトに直接書きます。
- `claude-collab` の置き場所が `skills/` から `codex-skills/` へ変わりました。Codex 側のシンボリックリンクを上記のコマンドで張り直してください。
<!-- lint:legacy-history end -->

## アーキテクチャ

4手法スキル（strong-inference / devils-advocate / dialectic-loop / contradiction-lift）から Codex を呼ぶ経路は `scripts/run-codex-role.sh` の 1 本だけです。中身は公式 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) の companion で、毎回新しいスレッド・読み取り専用で実行します。

```
Claude Code → scripts/run-codex-role.sh → codex-companion.mjs task --fresh --json → Codex
```

- **毎回新しいスレッド**: 継続（resume）は使いません。反復するときは、前回までの要約と必要な抜粋を貼った自己完結のプロンプトで投げ直します。
- **書き込みなし**: `--write` は受け付けません。ファイルが変更されていたら失敗として扱います。
- **成功の条件**: 終了コード 0 かつ JSON が読めて `status` が 0 かつ回答が空でないかつファイル変更なし。そのときだけ `answer.md` と `meta.json` を書きます。
- **作業ファイルは対象リポジトリの外**: `${XDG_STATE_HOME:-~/.local/state}/agent-dialectics/<repo-slug>/<method>/<task-id>/`

Codex から Claude を呼ぶ `claude-collab` スキルは `codex-skills/claude-collab/` にあり、Codex CLI 側のスキルとして動きます。

## プロジェクト構造

```
codex-collab/
├── .claude-plugin/
│   ├── plugin.json            # プラグインメタデータ
│   └── marketplace.json       # マーケットプレイス公開用メタデータ
├── scripts/
│   ├── run-codex-role.sh      # 4手法スキルの Codex 役呼び出し（公式 companion 経由）
│   ├── test-run-codex-role.sh # run-codex-role.sh のテスト
│   └── lint-plugin.sh         # プラグイン一貫性の検査
├── tests/
│   └── acceptance/            # 受け入れ試験（偽 companion・固定応答・チェックリスト）
├── skills/                    # Claude Code のスキル（4手法）
│   ├── strong-inference/
│   │   └── references/        # 仮説テンプレート
│   ├── devils-advocate/
│   │   └── references/        # 評価基準・批評テンプレート
│   ├── dialectic-loop/
│   │   └── references/        # 予測・帰納検証・アブダクションテンプレート
│   └── contradiction-lift/
│       └── references/        # 封緘解・矛盾マップ・止揚監査テンプレート
└── codex-skills/              # Codex CLI のスキル（Claude Code は読み込まない）
    └── claude-collab/
        ├── scripts/           # Codex から Claude を呼ぶ read-only ヘルパーとテスト
        └── references/        # Claude 相談・レビュー用テンプレート
```

## 使い方

### 4手法スキル共通

strong-inference / devils-advocate / dialectic-loop / contradiction-lift はスキル（`skills/<method>/SKILL.md`）として `/codex-collab:<method>` で起動します。Codex 役は公式 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) の companion を `scripts/run-codex-role.sh` 経由で毎回新しいスレッド・読み取り専用で呼びます（codex-plugin-cc のインストールが前提）。状態ファイルは対象リポジトリの外 `${XDG_STATE_HOME:-~/.local/state}/agent-dialectics/<repo-slug>/<method>/<task-id>/` に保存されます。

### `/codex-collab:strong-inference`

Strong Inference（強い推論）メソッドを使って、仮説駆動でバグ調査を行います。

```
# 基本的な使い方
/codex-collab:strong-inference APIが時々500エラーを返す

# モード指定
/codex-collab:strong-inference --mode claude-only テストがフレーキーな原因を調べて
```

**特徴:**
- 2-4個の競合仮説を生成
- 各仮説を排除する「キラー実験」を設計
- 仮説ツリーを状態ファイルに保存（調査状態を永続化）
- codexモードではCodexが仮説生成、Claudeが検証実行

### `/codex-collab:devils-advocate`

Devil's Advocate（悪魔の代弁者）メソッドを使って、設計案や仮説をストレステストします。

```
# 基本的な使い方
/codex-collab:devils-advocate このキャッシュ設計を検証して

# モード指定
/codex-collab:devils-advocate --mode claude-only マイクロサービス移行は妥当か

# ラウンド数指定
/codex-collab:devils-advocate --max-rounds 5 この認証設計
```

**特徴:**
- Blue Team（提案側）vs Red Team（批判側）の構造化議論
- 3ラウンド（デフォルト）の反論・再反論
- 最終評価: APPROVE / CONDITIONAL / REJECT
- codexモードではCodexがRed Team、ClaudeがBlue Team
- 議論ログを状態ファイルに保存

### `/codex-collab:dialectic-loop`

経験的な主張を Peirce の探究サイクル（演繹→帰納→仲裁）で現物データに照らして検証・精緻化します。

```
# 主張を corpus で検証
/codex-collab:dialectic-loop "このコードベースは合成を継承より好む" --corpus "src/**/*.ts"

# Codex に仮説生成から任せる（アブダクション variant）
/codex-collab:dialectic-loop --abduce --corpus "scripts/**/*.sh"
```

**特徴:**
- 演繹役（Claude）が反証可能な予測、帰納役（Codex, 独立）が現物コーパスをスクリプト集計＋反例探索、仲裁役（Claude）がスコアカードで H′ に更新
- `--abduce` で仮説生成自体を Codex に委譲（著者≠仲裁の独立性）
- 出力は「更新された仮説 H′ ＋ confidence ＋ 元の枠組みが見落とした点」
- ループログを状態ファイルに保存

### `/codex-collab:contradiction-lift`

Claude と Codex に**同じ問いを独立に解かせ**、答えの食い違いを止揚（アウフヘーベン）します。平均でも折衷でもなく、両者の真理契機を保存したまま一段高い枠へ。

```
# 実行で決着しない設計/価値の二択を止揚
/codex-collab:contradiction-lift "ループは段数固定か収束検知か"
```

**特徴:**
- 状態機械: contract → sealed → mapped → adjudicated → preserved → lifted → accepted | aporia | no_material_divergence
- 立場を事前割当せず、独立解の食い違いから矛盾を立ち上げる（devils-advocate の外部反対役とは逆）
- 出力は**選択機構 `f(C)→A|B|N`** か **正直なアポリア**（偽の総合に逃げない）
- 経験的に決着する対立は Codex 実行へ routing。ログを状態ファイルに保存

### スキルの自動起動

以下のようなリクエストで自動的にスキルが有効になります:
- 「このバグの原因を調査して」（Strong Inferenceスキル）
- 「仮説を立てて検証して」（Strong Inferenceスキル）
- 「この設計を批判的にレビューして」（Devil's Advocateスキル）
- 「反論をもらいたい」（Devil's Advocateスキル）
- 「この傾向分析の仮説をデータで検証して精緻化して」（Dialectic Loopスキル）
- 「主張を現物で裏取りしたい」「演繹と帰納で検証」（Dialectic Loopスキル）
- 「2つの案が食い違う、平均でなく止揚したい」（Contradiction Liftスキル）
- 「独立案を統合」「矛盾を止揚」「アウフヘーベン」（Contradiction Liftスキル）

### スキルの使い分け

**多くの場合、スキル名を覚える必要はありません**——やりたいことを自然文で書けば、内容から適切なスキルが自動的に起動します（上記「スキルの自動起動」）。能動的に選びたいとき・迷うときは、以下のガイドを参照してください。

| スキル | いつ使うか | 矛盾の出所 | 出力 |
|--------|-----------|-----------|------|
| `/codex-collab:strong-inference` | **未知の原因**を究明（バグ/デバッグ） | 競合仮説 | 根本原因＋証拠 |
| `/codex-collab:devils-advocate` | **1つの提案**を反証でストレステスト | 外から割り当てた反対役 | APPROVE/CONDITIONAL/REJECT |
| `/codex-collab:dialectic-loop` | **経験的主張**を現物データで検証・精緻化 | 予測 vs 現物の証拠 | 更新された仮説 H′＋confidence |
| `/codex-collab:contradiction-lift` | **独立した2つの解**の食い違いを止揚 | 独立解から自然に立ち上がる | 選択機構 or 正直なアポリア |

Codex 側から Claude を read-only の相談役として呼びたいときは、Codex で `claude-collab` スキルを使います。

#### 判断が難しいケース

**「検証/レビューしたい」と言われたら？**
- 原因不明の問題（なぜ動かない） → `strong-inference`（実験で仮説を排除）
- 1つの設計案の妥当性 → `devils-advocate`（反論で弱点を発見）
- 主張やトレンドが現物データと合うか → `dialectic-loop`（演繹→帰納→仲裁で精緻化）

**「2つの案で迷っている」と言われたら？**
- どちらか1案を叩いて弱点を見たい → `devils-advocate`
- 両方が良くて食い違う、平均でなく一段上で統合したい → `contradiction-lift`

#### 簡単な見分け方

```
「なぜ？」「原因は？」（未知の原因） → strong-inference
「これで良いか？」「弱点は？」      → devils-advocate
「主張をデータで検証/精緻化」      → dialectic-loop
「2つの良い案を平均でなく止揚」    → contradiction-lift
```

## ライセンス

MIT
