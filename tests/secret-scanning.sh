#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "error: install Gitleaks before running this test" >&2
  exit 1
fi

test_repo=$(mktemp -d)
trap 'rm -rf "$test_repo"' EXIT

cp "$project_root/.gitleaks.toml" "$test_repo/.gitleaks.toml"
mkdir -p "$test_repo/.githooks"
cp "$project_root/.githooks/pre-commit" "$test_repo/.githooks/pre-commit"
chmod +x "$test_repo/.githooks/pre-commit"

git -C "$test_repo" init -q
git -C "$test_repo" config user.name "Secret scan test"
git -C "$test_repo" config user.email "secret-scan@example.invalid"
git -C "$test_repo" config core.hooksPath .githooks
echo baseline >"$test_repo/fixture.txt"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm baseline

expect_rejected() {
  local fixture=$1
  local output
  git -C "$test_repo" add fixture.txt
  if output=$(cd "$test_repo" && .githooks/pre-commit 2>&1); then
    echo "error: Gitleaks accepted $fixture" >&2
    exit 1
  fi
  if grep -Fq -- "$(cat "$test_repo/fixture.txt")" <<<"$output"; then
    echo "error: Gitleaks printed the detected value for $fixture" >&2
    exit 1
  fi
  git -C "$test_repo" reset -q -- fixture.txt
  git -C "$test_repo" checkout -q -- fixture.txt
}

printf 'AKIA%s\n' 'ABCDEFGHIJKLMNOP' >"$test_repo/fixture.txt"
expect_rejected "fake AWS access key"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out "$test_repo/fixture.txt" 2>/dev/null
expect_rejected "disposable private key"

printf '%s\n' 'op://Employee/GITHUB_TOKEN/credential' >"$test_repo/fixture.txt"
git -C "$test_repo" add fixture.txt
if ! (cd "$test_repo" && .githooks/pre-commit >/dev/null); then
  echo "error: Gitleaks rejected an approved 1Password reference" >&2
  exit 1
fi

echo "Secret scanning tests passed."
