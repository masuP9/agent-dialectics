#!/usr/bin/env node
// Scripted mock of codex-plugin-cc's codex-companion.mjs (setup --json / task --json only).
// Inject with CODEX_COMPANION_PATH=<this file>. No model is called.
//
// setup:
//   MOCK_SETUP_JSON   JSON string printed instead of the default ready report
//   MOCK_SETUP_EXIT   exit code for setup (default 0)
// task:
//   MOCK_FIXTURES_DIR if set, the prompt's role marker
//                     `<!-- agent-dialectics-role: <method>/<role> -->` selects
//                     <dir>/<method>/<role>.json as the response
//                     (fields: rawOutput, status, touchedFiles, threadId; missing fields use defaults)
//   MOCK_TASK_STDOUT  raw stdout (overrides everything; used for invalid JSON)
//   MOCK_RAW_OUTPUT / MOCK_STATUS / MOCK_TOUCHED(JSON array) / MOCK_THREAD_ID  field overrides
//   MOCK_TASK_EXIT    exit code for task (default 0)
//   MOCK_STDERR       text written to stderr
//   MOCK_DELAY_SEC    sleep before answering (interrupt / resume tests)
// common:
//   MOCK_ARGS_LOG     file to append one JSON line per invocation: {argv, prompt}

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const argv = process.argv.slice(2);
const sub = argv[0];

function optionValue(name) {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
}

function sleep(sec) {
  return new Promise((resolve) => setTimeout(resolve, sec * 1000));
}

let prompt = null;
const promptFile = optionValue("--prompt-file");
if (promptFile) {
  prompt = fs.readFileSync(path.resolve(optionValue("--cwd") || process.cwd(), promptFile), "utf8");
}

if (process.env.MOCK_ARGS_LOG) {
  const pluginData = process.env.CLAUDE_PLUGIN_DATA ?? null;
  fs.appendFileSync(process.env.MOCK_ARGS_LOG, JSON.stringify({ argv, prompt, pluginData }) + "\n");
}

// Simulate the real companion's stale shared-broker record: when <CLAUDE_PLUGIN_DATA>/stale-broker
// exists, setup's auth check reuses the dead broker and reports loggedIn:false.
const staleBroker = Boolean(process.env.CLAUDE_PLUGIN_DATA) &&
  fs.existsSync(path.join(process.env.CLAUDE_PLUGIN_DATA, "stale-broker"));

if (sub === "setup") {
  const report = process.env.MOCK_SETUP_JSON
    ? JSON.parse(process.env.MOCK_SETUP_JSON)
    : staleBroker
      ? { ready: false, codex: { available: true }, auth: { loggedIn: false, detail: "connect ENOENT /tmp/cxc-stale/broker.sock" } }
      : { ready: true, codex: { available: true }, auth: { loggedIn: true } };
  console.log(JSON.stringify(report, null, 2));
  process.exit(Number(process.env.MOCK_SETUP_EXIT || 0));
}

if (sub !== "task") {
  console.error(`mock-companion: unsupported subcommand ${sub}`);
  process.exit(1);
}

if (process.env.MOCK_DELAY_SEC) {
  await sleep(Number(process.env.MOCK_DELAY_SEC));
}

if (process.env.MOCK_STDERR) {
  process.stderr.write(process.env.MOCK_STDERR + "\n");
}

const exitCode = Number(process.env.MOCK_TASK_EXIT || 0);

if (process.env.MOCK_TASK_STDOUT !== undefined) {
  process.stdout.write(process.env.MOCK_TASK_STDOUT);
  process.exit(exitCode);
}

let response = {};
if (process.env.MOCK_FIXTURES_DIR && prompt) {
  const m = prompt.match(/<!--\s*agent-dialectics-role:\s*([\w-]+)\/([\w-]+)\s*-->/);
  if (!m) {
    console.error("mock-companion: role marker not found in prompt");
    process.exit(1);
  }
  const fixture = path.join(process.env.MOCK_FIXTURES_DIR, m[1], `${m[2]}.json`);
  if (!fs.existsSync(fixture)) {
    console.error(`mock-companion: fixture not found: ${fixture}`);
    process.exit(1);
  }
  response = JSON.parse(fs.readFileSync(fixture, "utf8"));
}

const payload = {
  status: 0,
  threadId: crypto.randomUUID(),
  rawOutput: "mock answer",
  touchedFiles: [],
  reasoningSummary: [],
  ...response
};
if (process.env.MOCK_RAW_OUTPUT !== undefined) payload.rawOutput = process.env.MOCK_RAW_OUTPUT;
if (process.env.MOCK_STATUS !== undefined) payload.status = JSON.parse(process.env.MOCK_STATUS);
if (process.env.MOCK_TOUCHED !== undefined) payload.touchedFiles = JSON.parse(process.env.MOCK_TOUCHED);
if (process.env.MOCK_THREAD_ID !== undefined) payload.threadId = process.env.MOCK_THREAD_ID;

console.log(JSON.stringify(payload, null, 2));
process.exit(exitCode);
