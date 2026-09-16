#!/usr/bin/env bash
# report.sh — summarize request counts from an access log
set -euo pipefail

die() {
  echo "[error] $*" >&2
  exit 1
}

count_status() {
  awk '{print $9}' "$1" | sort | uniq -c | sort -rn
}

generate_report() {
  local log="$1"
  [ -r "$log" ] || die "cannot read log: $log"
  echo "# Status codes"
  count_status "$log"
}

[ $# -eq 1 ] || die "usage: report.sh <access.log>"
generate_report "$1"
