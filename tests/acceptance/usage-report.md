# ゲート A-2 利用量レポート（基準値）

ゲート A-2 の実モデル完走で行った **全 Codex 呼び出し** を記録する。表は次のコマンドで作る:

```sh
node tests/acceptance/collect-usage.mjs "<state-dir>" \
  --limit abduction=300000 --limit induction=300000 \
  --expect mapper=gpt-5.6-luna/low --expect hypothesis=gpt-6-astra/low ...
```

- `<state-dir>` は `${XDG_STATE_HOME:-~/.local/state}/agent-dialectics/<repo-slug>/<method>/<task-id>`
- rollout（`~/.codex/sessions/**/rollout-<timestamp>-<threadId>.jsonl`）が見つからない呼び出しは **測定不能＝不合格**
- 合格条件: turn 数 1（fresh）、sandbox `read-only`、prompt.md と user message が一致、model / effort が CLAUDE.md「利用量ポリシー」の期待値どおり、入力が上限以下（既定 10 万、ロール表で個別宣言したロールのみ例外）

## 実行環境

- 実施日: 2026-09-16（2 回目の再試験。1 回目の A-1 で F-1・F-2 が不合格、縮退警告の修正後に再実施）
- codex-cli: 0.154.0
- codex-plugin-cc companion: codex@openai-codex 1.0.6
- config.toml の model / effort: `gpt-6-astra` / `low`
- 作業用リポジトリ（cwd）: `/home/masup9/scratch/gate-a-target`（state dir は `~/.local/state/agent-dialectics/gate-a-target-f3b6cc81/`）

## strong-inference

state dir: `strong-inference/20260916-084537-15958`

| role-attempt | state | threadId | model | effort | sandbox | turns | input | cached | output | reasoning | verbatim | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| hypothesis-r1-1 | succeeded | 01a0a777-6b95-7491-88a3-491c4b126d45 | gpt-6-astra | low | read-only | 1 | 17685 | 12032 | 1246 | 47 | yes | 合格 |
| review-1 | succeeded | 01a0a77a-629d-7630-81b1-4a80349a332a | gpt-6-astra | low | read-only | 1 | 18246 | 7936 | 646 | 0 | yes | 合格 |

rows=2 failed=0

## contradiction-lift

state dir: `contradiction-lift/20260916-085343-4777`（到達先 aporia。Lift は Claude subagent が担当したため表に出ない）

| role-attempt | state | threadId | model | effort | sandbox | turns | input | cached | output | reasoning | verbatim | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| audit-r1-1 | succeeded | 01a0a793-bd09-7c33-ae37-f2bbde05d152 | gpt-6-astra | low | read-only | 1 | 22189 | 12160 | 1248 | 97 | yes | 合格 |
| audit-r2-1 | succeeded | 01a0a79b-db5c-78e3-a574-e53818be623f | gpt-6-astra | low | read-only | 1 | 23244 | 12160 | 1170 | 74 | yes | 合格 |
| mapper-1 | succeeded | 01a0a781-dcf1-7472-87ad-8e02f32e9121 | gpt-5.6-luna | low | read-only | 1 | 17121 | 9984 | 1610 | 80 | yes | 合格 |
| preserve-b-repair-1 | succeeded | 01a0a789-cf47-7910-8d13-831360cf9575 | gpt-6-astra | low | read-only | 1 | 19199 | 12160 | 1064 | 0 | yes | 合格 |
| preserve-b-rereview-1 | succeeded | 01a0a78b-e861-7861-bf05-24d88de88eff | gpt-6-astra | low | read-only | 1 | 19435 | 12160 | 45 | 38 | yes | 合格 |
| preserve-b-review-1 | succeeded | 01a0a787-7e94-7320-8d68-474de0d92378 | gpt-6-astra | low | read-only | 1 | 19805 | 12160 | 299 | 0 | yes | 合格 |
| preserve-b-steelman-1 | succeeded | 01a0a784-5e44-73d3-9688-13b8572e4fbe | gpt-6-astra | low | read-only | 1 | 18982 | 7936 | 742 | 0 | yes | 合格 |
| solver-b-1 | succeeded | 01a0a77e-52b2-7a52-b3e5-4487a553d384 | gpt-6-astra | low | read-only | 1 | 17462 | 12160 | 904 | 0 | yes | 合格 |

rows=8 failed=0

## dialectic-loop `--abduce`

state dir: `dialectic-loop/20260916-092932-5760`（abduction / induction は入力上限 30 万）

| role-attempt | state | threadId | model | effort | sandbox | turns | input | cached | output | reasoning | verbatim | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| abduction-1 | succeeded | 01a0a79f-0782-7a12-afaa-bd70bd533a46 | gpt-6-astra | low | read-only | 1 | 77615 | 67840 | 2098 | 102 | yes | 合格 |
| induction-r1-1 | succeeded | 01a0a7a2-1301-7e90-afe7-d1777a78a928 | gpt-6-astra | low | read-only | 1 | 97282 | 87552 | 2388 | 24 | yes | 合格 |
| induction-r2-1 | succeeded | 01a0a7a6-730c-7171-98ee-8625bdd49dc0 | gpt-6-astra | low | read-only | 1 | 81663 | 70912 | 2702 | 56 | yes | 合格 |

rows=3 failed=0

## 所見

- 上限超過・測定不能の呼び出しと対応: なし（3 手法あわせて 13 行、いずれも failed=0。rollout 未検出の行なし、最大入力は induction-r1-1 の 97282 で上限 30 万内、既定上限 10 万を使うロールも全件 10 万未満）
- 所見: strong-inference の `review-1` は exit 0・DONE・answer.md 2255B で正常終了していたが、実行セッションが完了通知を待たずに読み、「空の結果」と誤判定して `codex_call_failures` に exit 5 を記録し停止した。事実を伝えて既存 answer.md を採用させ完走（誤記録は取り消し済み）。応答が即時の mock では再現しないため、ゲート A-1 では検出できない
