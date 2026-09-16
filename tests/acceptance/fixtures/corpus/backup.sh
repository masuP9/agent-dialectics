#!/usr/bin/env bash
# backup.sh — archive a directory into BACKUP_ROOT
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/app}"

log_info() {
  echo "[info] $*"
}

die() {
  echo "[error] $*" >&2
  exit 1
}

backup_dir() {
  local src="$1"
  [ -d "$src" ] || die "source not found: $src"
  mkdir -p "$BACKUP_ROOT"
  tar -czf "$BACKUP_ROOT/$(basename "$src")-$(date +%Y%m%d).tar.gz" -C "$(dirname "$src")" "$(basename "$src")"
  log_info "archived $src"
}

[ $# -eq 1 ] || die "usage: backup.sh <dir>"
backup_dir "$1"
