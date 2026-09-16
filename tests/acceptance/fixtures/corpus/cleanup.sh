#!/usr/bin/env bash
# cleanup.sh — remove old temporary files
set -eu

TMP_ROOT="${TMP_ROOT:-/tmp/app}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-7}"

cleanup_tmp() {
  if [ ! -d "$TMP_ROOT" ]; then
    echo "nothing to clean: $TMP_ROOT" >&2
    exit 1
  fi
  find "$TMP_ROOT" -type f -mtime +"$MAX_AGE_DAYS" -delete
  echo "cleaned $TMP_ROOT"
}

cleanup_tmp
