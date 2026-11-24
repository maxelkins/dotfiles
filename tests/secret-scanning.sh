#!/usr/bin/env bash
# Runs .githooks/pre-commit in a throwaway repository and checks that it
# rejects fake secrets without printing them, and accepts 1Password references.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks is not installed" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stub Prettier so only the secret scan decides the result.
mkdir -p "$tmp/bin" "$tmp/repo/.githooks"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/prettier"
chmod +x "$tmp/bin/prettier"
export PATH="$tmp/bin:$PATH"

cp "$repo_root/.githooks/pre-commit" "$tmp/repo/.githooks/pre-commit"
cd "$tmp/repo"
git init -q
git config user.name test
git config user.email test@example.invalid
git config commit.gpgsign false
git config core.hooksPath .githooks
git add .githooks
git commit -qm init --no-verify

failed=0

# Fake secrets are built at run time so this file holds none.
random() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }

rejects() {
  local name="$1" value="$2" output
  printf '%s\n' "$value" >fixture
  git add fixture
  if output="$(.githooks/pre-commit 2>&1)"; then
    echo "FAIL: accepted $name" >&2
    failed=1
  elif [[ "$output" == *"$value"* ]]; then
    echo "FAIL: printed the value of $name" >&2
    failed=1
  else
    echo "ok: rejects $name"
  fi
  git rm -q --cached fixture
}

accepts() {
  local name="$1" value="$2"
  printf '%s\n' "$value" >fixture
  git add fixture
  if .githooks/pre-commit >/dev/null 2>&1; then
    echo "ok: accepts $name"
  else
    echo "FAIL: rejected $name" >&2
    failed=1
  fi
  git rm -q --cached fixture
}

rejects "GitHub token" "export GITHUB_TOKEN=ghp_$(random 36)"
rejects "generic API key" "export API_KEY=\"$(random 32)\""
rejects "private key" "$(printf -- '-----BEGIN %s-----\n' 'OPENSSH PRIVATE KEY'; head -c 600 /dev/urandom | base64; printf -- '-----END %s-----' 'OPENSSH PRIVATE KEY')"
accepts "1Password reference" 'export GITHUB_TOKEN="op://Employee/GITHUB_TOKEN/credential"'
accepts "op read" "export GITHUB_TOKEN=\"\$(op read 'op://Employee/GITHUB_TOKEN/credential')\""
accepts "gitleaks:allow" "export API_KEY=\"$(random 32)\" # gitleaks:allow"

exit "$failed"
