#!/usr/bin/env bash
# sync.sh — mirror the shared folder to the NAS

SRC="${SRC:-$HOME/shared}"
DEST="${DEST:-nas.internal:/volume1/shared}"

die() {
  echo "[error] $*" >&2
  exit 1
}

syncFiles() {
  rsync -a --delete "$SRC/" "$DEST/" || die "sync failed"
}

checkDest() {
  ping -c 1 -W 2 "${DEST%%:*}" > /dev/null || exit 2
}

checkDest
syncFiles
echo "synced $SRC -> $DEST"
