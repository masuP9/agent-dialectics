#!/usr/bin/env bash
# deploy.sh — deploy the app to the given environment
set -euo pipefail

log_info() {
  echo "[info] $*"
}

die() {
  echo "[error] $*" >&2
  exit 1
}

check_env() {
  case "$1" in
    staging|production) ;;
    *) die "unknown environment: $1" ;;
  esac
}

deploy_app() {
  local env="$1"
  check_env "$env"
  log_info "deploying to $env"
  if ! rsync -a ./dist/ "deploy@$env.internal:/srv/app/"; then
    die "rsync failed for $env"
  fi
  log_info "done"
}

[ $# -eq 1 ] || die "usage: deploy.sh <staging|production>"
deploy_app "$1"
