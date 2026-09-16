#!/usr/bin/env node
// Gate A-2 helper: build the usage report rows for every Codex role-attempt under a state dir.
//
// Usage:
//   node tests/acceptance/collect-usage.mjs <state-dir>
//        [--limit <role-prefix>=<tokens> ...] [--expect <role-prefix>=<model>/<effort> ...]
// Rollouts are read from $CODEX_HOME/sessions (default ~/.codex/sessions).
//
// For each <state-dir>/**/status.json (every run-codex-role.sh attempt, succeeded or failed;
// exit 1 / 2 attempts never reached Codex and are skipped) it takes threadId from meta.json or
// companion-stdout.json, finds rollout-*-<threadId>.jsonl and reports: model / effort / sandbox (turn_context),
// number of turns (fresh = 1), prompt verbatim match (trim(prompt.md) == trim(user message)),
// and the final token_count (input / cached / output / reasoning).
// A role whose rollout is missing is "測定不能" and FAILS (never silently passes).
// Exit 0 only when every row passes.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { attemptDirs, readJson, walk } from "./lib.mjs";

const args = process.argv.slice(2);
if (args.length === 0 || args[0].startsWith("--")) {
  console.error("usage: collect-usage.mjs <state-dir> [--limit role=N] [--expect role=model/effort]");
  process.exit(1);
}
const stateDir = path.resolve(args[0]);
const sessionsDir = path.join(process.env.CODEX_HOME || path.join(os.homedir(), ".codex"), "sessions");
const limits = [];
const expects = [];
for (let i = 1; i < args.length; i++) {
  const [flag, value] = [args[i], args[i + 1]];
  if (flag === "--limit") { const [k, v] = value.split("="); limits.push([k, Number(v)]); i++; }
  else if (flag === "--expect") { const [k, v] = value.split("="); const [m, e] = v.split("/"); expects.push([k, m, e]); i++; }
  else { console.error(`unknown argument: ${flag}`); process.exit(1); }
}
const DEFAULT_LIMIT = 100000;

// threadId → rollout path, built in one walk of the (unboundedly growing) sessions tree.
const rollouts = new Map();
for (const p of walk(sessionsDir, (name) => name.startsWith("rollout-") && name.endsWith(".jsonl"))) {
  const id = path.basename(p).replace(/^rollout-.*?-(?=[0-9a-f-]{36}\.jsonl$)/, "").replace(/\.jsonl$/, "");
  if (id) rollouts.set(id, p);
}

// A rollout holds every event of the turn; only three kinds are needed, so parse
// just those lines instead of the whole file (prompts run to ~100k tokens).
function readRollout(file) {
  const contexts = [];
  const userTexts = [];
  let usage = null;
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line) continue;
    const wanted = line.includes('"turn_context"') || line.includes('"token_count"') || line.includes('"user"');
    if (!wanted) continue;
    let ev;
    try { ev = JSON.parse(line); } catch { continue; }
    if (ev.type === "turn_context") contexts.push(ev.payload || {});
    else if (ev.type === "event_msg" && ev.payload?.type === "token_count") {
      usage = ev.payload?.info?.total_token_usage ?? usage;
    } else if (ev.type === "response_item" && ev.payload?.type === "message" && ev.payload?.role === "user") {
      userTexts.push((ev.payload.content || []).map((c) => c.text || "").join(""));
    }
  }
  return { contexts, userTexts, usage };
}

function lookup(table, role) {
  let best = null;
  for (const row of table) {
    if (role.startsWith(row[0]) && (!best || row[0].length > best[0].length)) best = row;
  }
  return best;
}

// Every attempt that reached the model counts, including failed ones (exit 4 / 5).
// Attempts that never reached Codex (exit 1 usage error, exit 2 Codex unavailable) are skipped.
const rows = [];
let failed = 0;

for (const attemptDir of attemptDirs(stateDir)) {
  const role = path.relative(stateDir, attemptDir);
  const status = readJson(path.join(attemptDir, "status.json")) || {};
  if (status.exit_code === 1 || status.exit_code === 2) continue;
  const meta = readJson(path.join(attemptDir, "meta.json"));
  const stdout = readJson(path.join(attemptDir, "companion-stdout.json"));
  const threadId = meta?.threadId || (typeof stdout?.threadId === "string" ? stdout.threadId : null);
  const promptPath = path.join(attemptDir, "prompt.md");
  const row = { role, threadId, state: status.state, problems: [] };
  if (status.state === "running") {
    row.problems.push("実行中（未完了）");
  }
  const rollout = threadId ? rollouts.get(threadId) : null;
  if (!rollout) {
    row.problems.push("測定不能（rollout なし）");
  } else {
    const { contexts, userTexts, usage } = readRollout(rollout);
    const ctx = contexts[0] || {};
    row.model = ctx.model;
    row.effort = ctx.effort;
    row.sandbox = ctx.sandbox_policy?.type;
    row.turns = contexts.length;
    if (!usage) {
      row.problems.push("測定不能（token_count なし）");
    } else {
      row.input = usage.input_tokens;
      row.cached = usage.cached_input_tokens;
      row.output = usage.output_tokens;
      row.reasoning = usage.reasoning_output_tokens;
      const limit = lookup(limits, path.basename(role))?.[1] ?? DEFAULT_LIMIT;
      if (row.input > limit) row.problems.push(`入力 ${row.input} > 上限 ${limit}`);
    }
    if (row.turns !== 1) row.problems.push(`turn 数 ${row.turns}（fresh なら 1）`);
    if (row.sandbox !== "read-only") row.problems.push(`sandbox ${row.sandbox}`);
    const prompt = fs.existsSync(promptPath) ? fs.readFileSync(promptPath, "utf8").trim() : null;
    row.verbatim = prompt !== null && userTexts.some((t) => t.trim() === prompt);
    if (!row.verbatim) row.problems.push("prompt.md と user message が不一致");
    const exp = lookup(expects, path.basename(role));
    if (exp) {
      if (exp[1] && row.model !== exp[1]) row.problems.push(`model ${row.model} ≠ 期待 ${exp[1]}`);
      if (exp[2] && row.effort !== exp[2]) row.problems.push(`effort ${row.effort} ≠ 期待 ${exp[2]}`);
    }
  }
  if (row.problems.length) failed++;
  rows.push(row);
}

console.log(`| role-attempt | state | threadId | model | effort | sandbox | turns | input | cached | output | reasoning | verbatim | 判定 |`);
console.log(`|---|---|---|---|---|---|---|---|---|---|---|---|---|`);
for (const r of rows) {
  const verdict = r.problems.length ? `不合格: ${r.problems.join("; ")}` : "合格";
  console.log(`| ${r.role} | ${r.state ?? ""} | ${r.threadId ?? ""} | ${r.model ?? ""} | ${r.effort ?? ""} | ${r.sandbox ?? ""} | ${r.turns ?? ""} | ${r.input ?? ""} | ${r.cached ?? ""} | ${r.output ?? ""} | ${r.reasoning ?? ""} | ${r.verbatim ? "yes" : "no"} | ${verdict} |`);
}
console.log(`\nrows=${rows.length} failed=${failed}`);
if (rows.length === 0) {
  console.log("Codex に届いた呼び出し（status.json）が 1 つもない → 不合格");
  process.exit(1);
}
process.exit(failed ? 1 : 0);
