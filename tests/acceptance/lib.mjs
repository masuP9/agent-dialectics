// Shared helpers for the gate A checkers. The filenames here mirror the output
// contract of scripts/run-codex-role.sh — keep them in sync with that script.

import fs from "node:fs";
import path from "node:path";

// Markers that identify one role-attempt directory. `status.json` is written first
// by the runner; the others cover a directory prepared before the run.
export const ATTEMPT_MARKERS = ["status.json", "prompt.md", ".claimed"];

export function walk(dir, pred, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, pred, out);
    else if (pred(ent.name, p)) out.push(p);
  }
  return out;
}

// Every role-attempt directory under stateDir, sorted.
export function attemptDirs(stateDir) {
  const found = [];
  const visit = (dir) => {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    if (dir !== stateDir && entries.some((e) => ATTEMPT_MARKERS.includes(e.name))) found.push(dir);
    for (const ent of entries) {
      if (ent.isDirectory() && ent.name !== ".claimed") visit(path.join(dir, ent.name));
    }
  };
  visit(stateDir);
  return found.sort();
}

// Read a JSON artifact, tolerating a missing or malformed file.
export function readJson(p) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return null;
  }
}
