#!/usr/bin/env bash
# lint-plugin.sh — Plugin consistency checks for codex-collab
# Checks:
#   1. Version sync between plugin.json and marketplace.json
#   2. bash blocks in commands/*.md: syntax + CODEX_SKILL_CONTEXT marker
#   3. (warning-only) boilerplate drift in HELPERS loading chains
#   4. SKILL.md frontmatter (skills/*/SKILL.md, codex-skills/*/SKILL.md): strict YAML,
#      name/description required strings, no duplicate keys
#   5. relative markdown links in SKILL.md / references/ resolve to existing files
#   6. forbidden references (legacy transport) = 0 in METHOD_SKILLS
#      (PR1: the 4 method skills only; PR2 widens this to the whole repo)
#   7. the shared Codex-role block (between the shared:codex-role-protocol markers)
#      is identical in the 4 method SKILL.md, apart from the method name
# Exit 0 on clean; non-zero on any error-level violation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0
WARNINGS=0

METHOD_SKILLS=(strong-inference devils-advocate dialectic-loop contradiction-lift)
FORBIDDEN_PATTERN='codex-helpers|codex_run_exec|CODEX_SKILL_CONTEXT|commands/codex-collab|collab-planning|codex-collab\.local\.md|mcp__codex'

# ─────────────────────────────────────────────
# Check 1: version sync
# ─────────────────────────────────────────────
check_version_sync() {
  local plugin_ver marketplace_ver
  plugin_ver="$(jq -r '.version' "$REPO_ROOT/.claude-plugin/plugin.json")"
  marketplace_ver="$(jq -r '.plugins[0].version' "$REPO_ROOT/.claude-plugin/marketplace.json")"

  if [ "$plugin_ver" = "$marketplace_ver" ]; then
    echo "[OK] Version sync: $plugin_ver"
  else
    echo "[ERROR] Version mismatch: plugin.json=$plugin_ver, marketplace.json=$marketplace_ver"
    ERRORS=$((ERRORS + 1))
  fi
}

# ─────────────────────────────────────────────
# Check 2: bash blocks in commands/*.md
# ─────────────────────────────────────────────
check_bash_blocks() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  local md_files=()
  for f in "$REPO_ROOT/commands/"*.md; do
    [ -f "$f" ] && md_files+=("$f")
  done

  if [ ${#md_files[@]} -eq 0 ]; then
    echo "[WARN] No commands/*.md files found"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  local total_blocks=0
  local syntax_errors=0
  local missing_marker=0

  for md_file in "${md_files[@]}"; do
    local fname
    fname="$(basename "$md_file")"
    local block_num=0
    local in_block=0
    local block_file=""

    # Extract bash blocks using awk; write each to a numbered temp file
    # We process line-by-line in a subshell to avoid nested bash issues
    while IFS= read -r line; do
      if [ "$in_block" -eq 0 ] && [ "$line" = '```bash' ]; then
        in_block=1
        block_num=$((block_num + 1))
        block_file="$tmpdir/${fname%.md}-block-$(printf '%03d' "$block_num").sh"
        : > "$block_file"
        continue
      fi
      if [ "$in_block" -eq 1 ] && [ "$line" = '```' ]; then
        in_block=0
        continue
      fi
      if [ "$in_block" -eq 1 ]; then
        printf '%s\n' "$line" >> "$block_file"
      fi
    done < "$md_file"

    local file_block_count="$block_num"
    total_blocks=$((total_blocks + file_block_count))

    # Validate each extracted block
    for bf in "$tmpdir/${fname%.md}-block-"*.sh; do
      [ -f "$bf" ] || continue
      local bname
      bname="$(basename "$bf")"
      local bnum="${bname##*-block-}"
      bnum="${bnum%.sh}"
      # Remove leading zeros for display
      local bnum_display
      bnum_display="$(printf '%d' "$((10#$bnum))")"

      # Syntax check
      if ! bash -n "$bf" 2>"$tmpdir/bash-err"; then
        local err_msg
        err_msg="$(cat "$tmpdir/bash-err")"
        echo "[ERROR] Syntax error in $fname block $bnum_display: $err_msg"
        ERRORS=$((ERRORS + 1))
        syntax_errors=$((syntax_errors + 1))
        continue
      fi

      # Marker check
      if ! grep -q 'CODEX_SKILL_CONTEXT=1' "$bf"; then
        echo "[ERROR] Missing CODEX_SKILL_CONTEXT marker in $fname block $bnum_display"
        ERRORS=$((ERRORS + 1))
        missing_marker=$((missing_marker + 1))
      fi
    done
  done

  echo "[OK] bash blocks checked: total=$total_blocks, syntax_errors=$syntax_errors, missing_marker=$missing_marker"
}

# ─────────────────────────────────────────────
# Check 3: boilerplate drift (warning only)
# ─────────────────────────────────────────────
# Canonical HELPERS loading chain (from CLAUDE.md):
#   HELPERS=""
#   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
#     HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
#   elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
#     HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh ...)
#   fi
#   [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ] && HELPERS="$(pwd)/scripts/codex-helpers.sh"
#   [ -f "$HELPERS" ] && source "$HELPERS"
#
# Non-canonical (short-form) variant: skips the cache lookup entirely —
#   HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
# This is the only form flagged as drift; the closing one-liner fallback is acceptable per CLAUDE.md.
check_boilerplate_drift() {
  local drift_found=0

  for md_file in "$REPO_ROOT/commands/"*.md; do
    [ -f "$md_file" ] || continue
    local fname
    fname="$(basename "$md_file")"

    # Count canonical chains (those with the full cache-lookup elif)
    # grep -c exits 1 on zero matches; || true prevents set -e from aborting
    local canonical
    canonical="$(grep -c 'plugins/cache/codex-collab/codex-collab' "$md_file" 2>/dev/null || true)"
    local short_form
    # SC2016: single quotes intentional — searching for literal text containing $(pwd)
    # shellcheck disable=SC2016
    short_form="$(grep -c 'CLAUDE_PLUGIN_ROOT:-\$(pwd)' "$md_file" 2>/dev/null || true)"

    if [ "$short_form" -gt 0 ]; then
      echo "[WARN] Boilerplate drift in $fname: canonical=$canonical, short-form=${short_form} (missing cache-lookup elif)"
      WARNINGS=$((WARNINGS + 1))
      drift_found=$((drift_found + 1))
    fi
  done

  if [ "$drift_found" -eq 0 ]; then
    echo "[OK] Boilerplate: no drift variants found"
  fi
}

# ─────────────────────────────────────────────
# Check 4: SKILL.md frontmatter (strict YAML)
# ─────────────────────────────────────────────
# The single source of truth for "what this repo lints": SKILL.md files (SKILL_FILES)
# and their references (SKILL_DOC_FILES = SKILL_FILES + references/**/*.md).
SKILL_FILES=()
SKILL_DOC_FILES=()
collect_skill_files() {
  local f
  for f in "$REPO_ROOT"/skills/*/SKILL.md "$REPO_ROOT"/codex-skills/*/SKILL.md; do
    [ -f "$f" ] && SKILL_FILES+=("$f")
  done
  SKILL_DOC_FILES=("${SKILL_FILES[@]}")
  while IFS= read -r f; do
    [ -n "$f" ] && SKILL_DOC_FILES+=("$f")
  done < <(find "$REPO_ROOT/skills" "$REPO_ROOT/codex-skills" -mindepth 3 -path '*/references/*' -name '*.md' 2>/dev/null)
}

check_skill_frontmatter() {
  local files=("${SKILL_FILES[@]}")
  if [ ${#files[@]} -eq 0 ]; then
    echo "[WARN] No SKILL.md files found"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  local out rc=0
  out="$(python3 - "$REPO_ROOT" "${files[@]}" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("[ERROR] PyYAML is required for the SKILL.md frontmatter check")
    sys.exit(1)

class StrictLoader(yaml.SafeLoader):
    pass

def construct_mapping(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(None, None, f"duplicate key: {key}", key_node.start_mark)
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)

StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_mapping)

root = sys.argv[1]
errors = 0
for path in sys.argv[2:]:
    rel = path[len(root) + 1:]
    text = open(path, encoding="utf-8").read()
    if not text.startswith("---\n"):
        print(f"[ERROR] {rel}: missing frontmatter")
        errors += 1
        continue
    end = text.find("\n---", 4)
    if end < 0:
        print(f"[ERROR] {rel}: unterminated frontmatter")
        errors += 1
        continue
    try:
        data = yaml.load(text[4:end], Loader=StrictLoader)
    except Exception as e:  # YAMLError, or TypeError for unhashable keys such as `? [a, b]`
        msg = (str(e).splitlines() or [type(e).__name__])[0]
        print(f"[ERROR] {rel}: invalid YAML frontmatter: {msg}")
        errors += 1
        continue
    if not isinstance(data, dict):
        print(f"[ERROR] {rel}: frontmatter is not a mapping")
        errors += 1
        continue
    for field in ("name", "description"):
        if not isinstance(data.get(field), str) or not data.get(field).strip():
            print(f"[ERROR] {rel}: '{field}' must be a non-empty string")
            errors += 1
print(f"[OK] SKILL.md frontmatter checked: files={len(sys.argv) - 2}, errors={errors}")
sys.exit(1 if errors else 0)
PY
)" || rc=$?
  count_python_errors "$rc" "$out"
}

# Add the [ERROR] lines of a python check to ERRORS; a non-zero exit without any
# [ERROR] line (e.g. an uncaught exception) still counts as one error.
count_python_errors() {
  local rc="$1" out="$2" n
  echo "$out"
  [ "$rc" -eq 0 ] && return 0
  n="$(printf '%s\n' "$out" | grep -c '^\[ERROR\]' || true)"
  if [ "$n" -eq 0 ]; then
    echo "[ERROR] check exited $rc without reporting errors"
    n=1
  fi
  ERRORS=$((ERRORS + n))
}

# ─────────────────────────────────────────────
# Check 5: relative links in SKILL.md / references
# ─────────────────────────────────────────────
check_relative_links() {
  local out rc=0
  out="$(python3 - "$REPO_ROOT" "${SKILL_DOC_FILES[@]}" <<'PY'
import os, re, sys
root = sys.argv[1]
files = sys.argv[2:]
inline_re = re.compile(r"\[[^\]]*\]\(\s*(<[^>]*>|[^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)")
refdef_re = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)")
fence_re = re.compile(r"^\s*(```|~~~)")
errors = 0
for path in sorted(files):
    rel = os.path.relpath(path, root)
    in_fence = False
    for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
        if fence_re.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        targets = inline_re.findall(line) + refdef_re.findall(line)
        for target in targets:
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1].strip()
            if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
                continue
            target_path = target.split("#", 1)[0]
            if not target_path:
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target_path))
            if not os.path.exists(resolved):
                print(f"[ERROR] {rel}:{lineno}: broken relative link: {target}")
                errors += 1
print(f"[OK] relative links checked: files={len(files)}, broken={errors}")
sys.exit(1 if errors else 0)
PY
)" || rc=$?
  count_python_errors "$rc" "$out"
}

# ─────────────────────────────────────────────
# Check 6: forbidden legacy references
# ─────────────────────────────────────────────
check_forbidden_references() {
  local targets=() s
  for s in "${METHOD_SKILLS[@]}"; do
    [ -d "$REPO_ROOT/skills/$s" ] && targets+=("$REPO_ROOT/skills/$s")
  done
  if [ ${#targets[@]} -eq 0 ]; then
    # grep -r with no path would scan the current directory instead
    echo "[ERROR] forbidden references: none of ${METHOD_SKILLS[*]} exist under skills/"
    ERRORS=$((ERRORS + 1))
    return
  fi
  local hits
  hits="$(grep -rnE "$FORBIDDEN_PATTERN" "${targets[@]}" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | while IFS= read -r line; do
      echo "[ERROR] forbidden reference: ${line#"$REPO_ROOT"/}"
    done
    ERRORS=$((ERRORS + $(printf '%s\n' "$hits" | wc -l)))
  else
    echo "[OK] forbidden references: 0 in ${METHOD_SKILLS[*]}"
  fi
}

# ─────────────────────────────────────────────
# Check 7: the shared Codex-role block is identical in the 4 method skills
# ─────────────────────────────────────────────
check_shared_block() {
  local out rc=0
  out="$(python3 - "$REPO_ROOT" "${METHOD_SKILLS[@]}" <<'PY'
import os, re, sys

root, methods = sys.argv[1], sys.argv[2:]
START = "<!-- shared:codex-role-protocol start"
END = "<!-- shared:codex-role-protocol end -->"
blocks, errors = {}, 0
for m in methods:
    path = os.path.join(root, "skills", m, "SKILL.md")
    rel = os.path.relpath(path, root)
    text = open(path, encoding="utf-8").read()
    start, end = text.find(START), text.find(END)
    if start < 0 or end < 0 or end < start:
        print(f"[ERROR] {rel}: shared:codex-role-protocol markers missing")
        errors += 1
        continue
    body = text[text.index("\n", start) + 1:end]
    # The method name is the only legitimate difference between the copies.
    blocks[rel] = re.sub("|".join(re.escape(x) for x in methods), "<method>", body)

if blocks and errors == 0:
    reference, expected = next(iter(blocks.items()))
    for rel, body in blocks.items():
        if body != expected:
            print(f"[ERROR] {rel}: shared:codex-role-protocol block differs from {reference} (keep the 4 copies in sync)")
            errors += 1
print(f"[OK] shared block checked: files={len(methods)}, mismatches={errors}")
sys.exit(1 if errors else 0)
PY
)" || rc=$?
  count_python_errors "$rc" "$out"
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
  echo "=== codex-collab plugin consistency lint ==="
  echo ""

  echo "-- Check 1: Version sync --"
  check_version_sync
  echo ""

  echo "-- Check 2: bash blocks (syntax + CODEX_SKILL_CONTEXT marker) --"
  check_bash_blocks
  echo ""

  echo "-- Check 3: boilerplate drift (warning only) --"
  check_boilerplate_drift
  echo ""

  collect_skill_files

  echo "-- Check 4: SKILL.md frontmatter --"
  check_skill_frontmatter
  echo ""

  echo "-- Check 5: relative links --"
  check_relative_links
  echo ""

  echo "-- Check 6: forbidden references --"
  check_forbidden_references
  echo ""

  echo "-- Check 7: shared Codex-role block --"
  check_shared_block
  echo ""

  echo "=== Summary: errors=$ERRORS, warnings=$WARNINGS ==="

  if [ "$ERRORS" -gt 0 ]; then
    echo "FAIL: $ERRORS error(s) found."
    exit 1
  else
    echo "PASS"
    exit 0
  fi
}

main "$@"
