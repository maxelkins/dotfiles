#!/usr/bin/env bash
set -euo pipefail

printf "setup.sh is retained for compatibility; use './dot init' next time.\n"
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dot" init "$@"
