#!/usr/bin/env bash
# rotate-logs.sh — gzip logs older than one day
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/app}"

log_info() {
  echo "[info] $*"
}

rotate_logs() {
  local n=0
  for f in "$LOG_DIR"/*.log; do
    [ -e "$f" ] || continue
    if [ "$(find "$f" -mtime +1)" ]; then
      gzip "$f"
      n=$((n + 1))
    fi
  done
  log_info "rotated $n file(s)"
}

rotate_logs
