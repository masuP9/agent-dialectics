# agent-dialectics

Claude Code と OpenAI Codex に**別々のモデルとして同じ問題を考えさせる**ための、4つの思考手法プラグイン。

同じモデルに考え直させても、同じ偏りが返ってきます。この 4手法は、Claude と Codex という**独立した 2つのモデル**に別々の役を割り当てて、片方だけでは出てこない指摘・反証・食い違いを取り出すためのものです。

| 手法 | 何をするか |
|------|-----------|
| strong-inference | 競合する仮説を立て、排除実験で未知の原因を絞り込む |
| devils-advocate | 1つの提案に反対役を当て、反証でストレステストする |
| dialectic-loop | 経験的な主張を現物データで確かめ、仮説を更新する |
| contradiction-lift | 独立に解いた 2つの答えの食い違いを、平均でなく一段上で統合する |

このプラグインは**考えさせるためのもの**で、実装や計画そのものの委譲は扱いません（それは公式 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) の役目です）。

## 前提条件

- OpenAI Codex CLI (`codex`) がインストール済みで、ログイン済みであること
  - **検証済み: codex-cli 0.154.0 / 対応対象: 0.154.0 以上**（それ未満は保証対象外）
- 公式プラグイン [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) がインストール済みであること（4手法の Codex 役はこの companion を経由して呼びます）
- Codex から `claude-collab` を使う場合は Claude Code CLI (`claude`) がインストール済みであること

## インストール

### Claude Code から使う

```bash
# マーケットプレイスを追加
/plugin marketplace add https://github.com/masuP9/agent-dialectics

# プラグインをインストール
/plugin install agent-dialectics@agent-dialectics
```

### Codex から使う

Codex のスキルディレクトリへシンボリックリンクを作成します。

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -sfn "$(pwd)/codex-skills/claude-collab" "${CODEX_HOME:-$HOME/.codex}/skills/claude-collab"
```

`claude-collab` は Codex 専用なので `codex-skills/` に置いています。Claude Code はこのディレクトリをスキルとして読み込まないため、Claude 側のスキル一覧には出てきません。

Codex で「Claude と一緒に実装して」「Claude にレビューしてもらって」のように依頼すると、`claude-collab` スキルが Claude Code CLI を read-only の相談役として呼び出します。

### 以前のバージョンから移行する場合（v0.40 以前）

<!-- lint:legacy-history start -->
- v0.41.0 でプラグイン名を `codex-collab` から `agent-dialectics` に変えました。古いプラグインとマーケットプレイスを外してから、上記のコマンドで入れ直してください。スキルの呼び出しも `/codex-collab:<method>` から `/agent-dialectics:<method>` に変わります。
- v0.40.0 で `/codex-collab`・`/collab-planning` コマンドと共通ヘルパー・PreToolUse フックを削除しました。実装や計画の委譲は公式 codex-plugin-cc をお使いください。
- v0.40.0 で `.claude/codex-collab.local.md` による設定を廃止しました。応答の言語は各スキルがプロンプトに直接書きます。
- v0.40.0 で `claude-collab` の置き場所が `skills/` から `codex-skills/` へ変わりました。Codex 側のシンボリックリンクを上記のコマンドで張り直してください。
- v0.38.0 で `codex mcp-server` 経路を廃止しました。MCP 設定（例: `~/.mcp.json` や `~/.claude.json` の `mcpServers.codex`）に `codex mcp-server` が残っていると Claude Code 起動時に接続エラーになるので、そのエントリを削除してください。
<!-- lint:legacy-history end -->

## 使い方

**多くの場合、スキル名を覚える必要はありません**——やりたいことを自然文で書けば、内容から適切なスキルが自動的に起動します。能動的に選びたいときは `/agent-dialectics:<method>` で直接呼べます。

### `/agent-dialectics:strong-inference`

競合する仮説を立て、それぞれを**排除する実験**を設計して、未知の原因を絞り込みます（バグ調査・デバッグ向け）。

```
/agent-dialectics:strong-inference APIが時々500エラーを返す
/agent-dialectics:strong-inference --mode claude-only テストがフレーキーな原因を調べて
```

- 2〜4個の競合仮説を立てる
- それぞれを潰せる「キラー実験」を設計する
- 仮説ツリーを状態ファイルに残すので、途中で中断しても続きから再開できる
- Codex が仮説を立て、Claude が検証を実行する（`--mode claude-only` で Claude だけでも回せる）

### `/agent-dialectics:devils-advocate`

1つの設計案に**反対役を外から当てて**、反証でストレステストします。

```
/agent-dialectics:devils-advocate このキャッシュ設計を検証して
/agent-dialectics:devils-advocate --mode claude-only マイクロサービス移行は妥当か
/agent-dialectics:devils-advocate --max-rounds 5 この認証設計
```

- 提案側と批判側に分かれて、既定 3 ラウンドの反論・再反論を行う
- Codex が批判側、Claude が提案側（`--mode claude-only` で Claude だけでも回せる）
- 最後に「承認 / 条件付き承認 / 却下」で結論を出す
- 議論のログを状態ファイルに残す

### `/agent-dialectics:dialectic-loop`

経験的な主張を、演繹（予想を立てる）→ 帰納（現物データで確かめる）→ 仲裁（突き合わせて更新する）の順で精緻化します。

```
# 主張を現物のコードで検証する
/agent-dialectics:dialectic-loop "このコードベースは合成を継承より好む" --corpus "src/**/*.ts"

# 仮説を立てるところから Codex に任せる
/agent-dialectics:dialectic-loop --abduce --corpus "scripts/**/*.sh"
```

- Claude が反証できる形の予想を立て、Codex が独立に現物データを集計して反例を探し、Claude が突き合わせて仮説を更新する
- `--abduce` を付けると、仮説を立てるところ自体を Codex に任せる（立てた側と裁く側を分ける）
- 出力は「更新された仮説 ＋ どれだけ確からしいか ＋ 元の枠組みが見落としていた点」
- ループのログを状態ファイルに残す

### `/agent-dialectics:contradiction-lift`

Claude と Codex に**同じ問いを独立に解かせ**、答えの食い違いを止揚（アウフヘーベン）します。平均でも折衷でもなく、両者の言い分の正しい部分を残したまま一段高い枠へ。

```
/agent-dialectics:contradiction-lift "ループは段数固定か収束検知か"
```

- 立場を事前に割り当てず、独立に解かせた答えの食い違いから対立を立ち上げる（devils-advocate の外から当てる反対役とは逆）
- 出力は**どちらを選ぶかを決める規則**か、**正直な行き詰まりの宣言**（無理に折衷しない）
- 実際に動かせば決着する対立は、Codex での実行へ回す
- ログを状態ファイルに残す

## スキルの使い分け

| スキル | いつ使うか | 食い違いの出どころ | 出力 |
|--------|-----------|-----------|------|
| `/agent-dialectics:strong-inference` | **未知の原因**を究明（バグ/デバッグ） | 競合する仮説 | 根本原因＋証拠 |
| `/agent-dialectics:devils-advocate` | **1つの提案**を反証でストレステスト | 外から割り当てた反対役 | 承認／条件付き承認／却下 |
| `/agent-dialectics:dialectic-loop` | **経験的主張**を現物データで検証・精緻化 | 予想 vs 現物の証拠 | 更新された仮説＋どれだけ確からしいか |
| `/agent-dialectics:contradiction-lift` | **独立した2つの解**の食い違いを止揚 | 独立に解いた答えから自然に立ち上がる | 選択の規則、または正直な行き詰まり |

### 迷ったときの見分け方

```
「なぜ？」「原因は？」（未知の原因） → strong-inference
「これで良いか？」「弱点は？」      → devils-advocate
「主張をデータで検証/精緻化」      → dialectic-loop
「2つの良い案を平均でなく止揚」    → contradiction-lift
```

**「検証/レビューしたい」と言われたとき**

- 原因不明の問題（なぜ動かない） → `strong-inference`（実験で仮説を潰す）
- 1つの設計案の妥当性 → `devils-advocate`（反論で弱点を出す）
- 主張やトレンドが現物データと合うか → `dialectic-loop`（予想→確認→更新）

**「2つの案で迷っている」と言われたとき**

- どちらか 1案を叩いて弱点を見たい → `devils-advocate`
- 両方が良くて食い違う、平均でなく一段上で統合したい → `contradiction-lift`

Codex 側から Claude を read-only の相談役として呼びたいときは、Codex で `claude-collab` スキルを使います。

## 仕組み

4手法スキルから Codex を呼ぶ経路は `scripts/run-codex-role.sh` の 1 本だけです。中身は公式 [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) の companion で、毎回新しいスレッド・読み取り専用で実行します。

```
Claude Code → scripts/run-codex-role.sh → codex-companion.mjs task --fresh --json → Codex
```

- **毎回新しいスレッド**: 続き（resume）は使いません。反復するときは、前回までの要約と必要な抜粋を貼った自己完結のプロンプトで投げ直します。
- **書き込みなし**: `--write` は受け付けません。ファイルが変更されていたら失敗として扱います。
- **成功の条件**: 終了コード 0 かつ JSON が読めて `status` が 0 かつ回答が空でないかつファイル変更なし。そのときだけ `answer.md` と `meta.json` を書きます。
- **作業ファイルは対象リポジトリの外**: `${XDG_STATE_HOME:-~/.local/state}/agent-dialectics/<repo-slug>/<method>/<task-id>/` に置くので、調べている対象のリポジトリは汚れません。

Codex から Claude を呼ぶ `claude-collab` スキルは `codex-skills/claude-collab/` にあり、Codex CLI 側のスキルとして動きます。

## プロジェクト構造

```
agent-dialectics/
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

## ライセンス

MIT
