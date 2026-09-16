#!/usr/bin/env node
// Gate A-1 non-leak check: every Codex role-attempt under <state-dir> must record an
// inputs.json that stays within the allowlist.
//
// Usage: node tests/acceptance/check-inputs.mjs <state-dir> [allowlist.json]
//   allowlist.json (default: tests/acceptance/fixtures/inputs-allowlist.json):
//   { "<method>/<role>": ["<state.md section>", ...], ... }
//   Round suffixes are stripped before lookup (critic-r2 → critic).
//   "<N>" / "<N-1>" inside a section name matches any round number.
//
// An attempt directory is any directory containing prompt.md, status.json or .claimed.
// Each one fails unless:
//   - inputs.json exists and parses, with string method / role and array state_sections / artifacts
//   - every state_sections entry is allowed for the role
//   - inputs.json is a JSON object (null / arrays / scalars fail)
//   - no artifact path points inside the agent-dialectics state root (or <state-dir> when the
//     root is not an ancestor): state content must go through state_sections, so no role's
//     answer.md / prompt.md — from this task or another — can be passed as an artifact.
//     Artifacts outside the state root (templates, repo files) are not checked per role.
//   - prompt.md line 1 is the role marker matching inputs.json
// Exit 0 only when every attempt passes and at least one was found.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { attemptDirs, readJson } from "./lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const stateDirArg = process.argv[2];
const allowPath = process.argv[3] || path.join(here, "fixtures", "inputs-allowlist.json");
if (!stateDirArg) {
  console.error("usage: check-inputs.mjs <state-dir> [allowlist.json]");
  process.exit(1);
}
const stateDir = fs.realpathSync(path.resolve(stateDirArg));
const allow = JSON.parse(fs.readFileSync(allowPath, "utf8"));

function sectionPatterns(allowed) {
  return allowed.map((a) =>
    new RegExp("^" + a.split(/<N(?:-1)?>/).map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("\\d+") + "$")
  );
}

// Artifacts must not come from any method state: the nearest ancestor named "agent-dialectics"
// (the XDG state root) covers other tasks' answer.md too; fall back to <state-dir> itself.
const stateRoot = (() => {
  let d = stateDir;
  while (path.dirname(d) !== d) {
    if (path.basename(d) === "agent-dialectics") return d;
    d = path.dirname(d);
  }
  return stateDir;
})();

function insideStateRoot(p) {
  let resolved = path.resolve(p);
  try { resolved = fs.realpathSync(resolved); } catch { /* keep lexical path for missing files */ }
  const rel = path.relative(stateRoot, resolved);
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

const attempts = attemptDirs(stateDir);
let failed = 0;
for (const dir of attempts) {
  const rel = path.relative(stateDir, dir);
  const problems = [];
  const inputsPath = path.join(dir, "inputs.json");
  let inputs = null;
  if (!fs.existsSync(inputsPath)) {
    problems.push("inputs.json がない");
  } else {
    inputs = readJson(inputsPath);
    if (inputs === null) {
      problems.push("inputs.json が JSON として読めない");
    } else if (typeof inputs !== "object" || Array.isArray(inputs)) {
      problems.push("inputs.json がオブジェクトでない");
      inputs = null;
    }
  }

  if (inputs) {
    if (typeof inputs.method !== "string" || !inputs.method) problems.push("method がない");
    if (typeof inputs.role !== "string" || !inputs.role) problems.push("role がない");
    if (!Array.isArray(inputs.state_sections)) problems.push("state_sections が配列でない");
    if (!Array.isArray(inputs.artifacts)) problems.push("artifacts が配列でない");

    if (typeof inputs.method === "string" && typeof inputs.role === "string") {
      const key = `${inputs.method}/${inputs.role.replace(/-r\d+$/, "")}`;
      const allowed = allow[key];
      if (!allowed) {
        problems.push(`allowlist にロール ${key} がない`);
      } else if (Array.isArray(inputs.state_sections)) {
        const patterns = sectionPatterns(allowed);
        for (const s of inputs.state_sections) {
          if (typeof s !== "string" || !patterns.some((re) => re.test(s))) problems.push(`許可されていない節: ${s}`);
        }
      }
      const promptPath = path.join(dir, "prompt.md");
      if (fs.existsSync(promptPath)) {
        const first = fs.readFileSync(promptPath, "utf8").split("\n", 1)[0].trim();
        const expected = `<!-- agent-dialectics-role: ${inputs.method}/${inputs.role} -->`;
        if (first !== expected) problems.push(`prompt.md 1 行目が ${expected} でない`);
      } else {
        problems.push("prompt.md がない");
      }
    }

    if (Array.isArray(inputs.artifacts)) {
      for (const a of inputs.artifacts) {
        if (typeof a !== "string" || !path.isAbsolute(a)) problems.push(`artifacts が絶対パスでない: ${a}`);
        else if (insideStateRoot(a)) problems.push(`手法の状態ディレクトリ内のファイルを成果物として渡している: ${a}`);
      }
    }
  }

  if (problems.length) {
    failed++;
    console.log(`NG ${rel}: ${problems.join("; ")}`);
  } else {
    console.log(`OK ${rel}`);
  }
}
console.log(`\nchecked=${attempts.length} failed=${failed}`);
process.exit(attempts.length === 0 || failed ? 1 : 0);
