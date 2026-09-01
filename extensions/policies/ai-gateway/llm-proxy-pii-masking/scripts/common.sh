#!/usr/bin/env bash
# Shared config + helpers for the gateway provisioning scripts.
# Reads OPENAI_API_KEY from the repo-root .env (see .env.example).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*" >&2; }
info() { printf '    %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_env() {
  [[ -n "${OPENAI_API_KEY:-}" ]] ||
    die "OPENAI_API_KEY is not set — copy .env.example to .env at the repo root and fill it in"
}

require_tools() {
  command -v jq >/dev/null || die "jq is required (sudo apt install jq / brew install jq)"
  command -v curl >/dev/null || die "curl is required"
  command -v envsubst >/dev/null || die "envsubst is required (gettext package)"
  command -v unzip >/dev/null || die "unzip is required"
  command -v docker >/dev/null || die "docker is required"
}
