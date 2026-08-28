#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)

if [ ! -x "$repo_root/.githooks/pre-commit" ]; then
  echo "error: $repo_root/.githooks/pre-commit is not executable" >&2
  exit 1
fi

git -C "$repo_root" config core.hooksPath .githooks
echo "--> Git hooks"
echo "    Using $repo_root/.githooks"
