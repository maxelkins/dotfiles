#!/usr/bin/env bash
# Checks the secret safeguards: .gitignore keeps credential files out, the
# pre-commit hook and CI's history scan reject fake secrets without printing
# them, and 1Password references pass.
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
# head closes the pipe early; that SIGPIPE is expected.
random() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1" || true; }

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

# .gitignore, checked against the real repository.
for path in home/.pi/agent/auth.json home/.pi/agent/settings.json \
  home/.pi/agent/sessions/session.jsonl home/.pi/agent/new-file.json \
  home/.ssh/id_ed25519 server.pem tls.key .env.local credentials.json; do
  if git -C "$repo_root" check-ignore -q --no-index "$path"; then
    echo "ok: ignores $path"
  else
    echo "FAIL: does not ignore $path" >&2
    failed=1
  fi
done
tracked_ignored="$(git -C "$repo_root" ls-files -ci --exclude-standard)"
if [[ -n "$tracked_ignored" ]]; then
  printf 'FAIL: tracked files match .gitignore:\n%s\n' "$tracked_ignored" >&2
  failed=1
fi

rejects "GitHub token" "export GITHUB_TOKEN=ghp_$(random 36)"
rejects "generic API key" "export API_KEY=\"$(random 32)\""
rejects "private key" "$(printf -- '-----BEGIN %s-----\n' 'OPENSSH PRIVATE KEY'; head -c 600 /dev/urandom | base64; printf -- '-----END %s-----' 'OPENSSH PRIVATE KEY')"
accepts "1Password reference" 'export GITHUB_TOKEN="op://Employee/GITHUB_TOKEN/credential"'
accepts "op read" "export GITHUB_TOKEN=\"\$(op read 'op://Employee/GITHUB_TOKEN/credential')\""
accepts "gitleaks:allow" "export API_KEY=\"$(random 32)\" # gitleaks:allow"

# CI's command: a secret committed without the hook must fail the history scan.
value="ghp_$(random 36)"
printf 'export GITHUB_TOKEN=%s\n' "$value" >fixture
git add fixture
git commit -qm "skip the hook" --no-verify
if output="$(gitleaks git --redact --verbose --no-banner . 2>&1)"; then
  echo "FAIL: history scan accepted a committed token" >&2
  failed=1
elif [[ "$output" == *"$value"* ]]; then
  echo "FAIL: history scan printed the token" >&2
  failed=1
else
  echo "ok: history scan rejects a committed token"
fi

exit "$failed"
