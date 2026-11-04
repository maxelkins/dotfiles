#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() {
  printf 'ok - %s\n' "$1"
}

fail_test() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local value="$1"
  local expected="$2"
  local name="$3"
  if [[ "$value" == *"$expected"* ]]; then
    pass "$name"
  else
    printf 'Expected output to contain: %s\n%s\n' "$expected" "$value" >&2
    fail_test "$name"
  fi
}

non_tty_output="$(printf '' | "$ROOT/dot")"
assert_contains "$non_tty_output" 'Usage: dot [command]' 'no-argument non-TTY invocation prints help'

if command -v python3 >/dev/null 2>&1; then
  if python3 - "$ROOT" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

root = sys.argv[1]
master, slave = pty.openpty()
process = subprocess.Popen([os.path.join(root, "dot")], cwd=root, stdin=slave, stdout=slave, stderr=slave)
os.close(slave)
output = b""
deadline = time.time() + 5
while b"Choose an operation:" not in output and time.time() < deadline:
    readable, _, _ = select.select([master], [], [], 0.1)
    if readable:
        output += os.read(master, 4096)
os.write(master, b"q\n")
process.wait(timeout=5)
os.close(master)
if b"Dotfiles" not in output or b"Current package profile:" not in output:
    sys.stderr.write(output.decode(errors="replace"))
    raise SystemExit(1)
PY
  then
    pass 'no-argument TTY invocation opens the menu'
  else
    fail_test 'no-argument TTY invocation opens the menu'
  fi
fi

menu_output="$({
  source "$ROOT/dot"
  cmd_setup() { printf 'DISPATCH setup\n'; }
  cmd_upgrade() { printf 'DISPATCH upgrade\n'; }
  cmd_check() { printf 'DISPATCH check\n'; }
  cmd_apply() { printf 'DISPATCH apply:%s\n' "$*"; }
  interactive_menu <<'INPUT'
1
2
3
4
1
4
2
4
3
x
q
INPUT
} 2>&1)"
assert_contains "$menu_output" 'DISPATCH setup' 'setup menu choice uses command dispatch'
assert_contains "$menu_output" 'DISPATCH upgrade' 'upgrade menu choice uses command dispatch'
assert_contains "$menu_output" 'DISPATCH check' 'check menu choice uses command dispatch'
assert_contains "$menu_output" 'DISPATCH apply:home' 'home apply menu choice uses command dispatch'
assert_contains "$menu_output" 'DISPATCH apply:macos' 'macOS apply menu choice uses command dispatch'
assert_contains "$menu_output" 'DISPATCH apply:dock' 'Dock apply menu choice uses command dispatch'
assert_contains "$menu_output" "Invalid choice 'x'" 'invalid menu choice returns a useful message'

profile_home="$(mktemp -d)"
HOME="$profile_home" bash -c 'source "$1/dot"; interactive_menu' _ "$ROOT" <<'INPUT' >/dev/null
5
3
q
INPUT
if [[ "$(<"$profile_home/.config/mac-setup/profile")" == work ]]; then
  pass 'profile menu saves the selected local profile'
else
  fail_test 'profile menu saves the selected local profile'
fi
rm -rf "$profile_home"

repo="$(mktemp -d)"
git -C "$repo" init -q
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
printf 'test\n' > "$repo/file"
git -C "$repo" add file
git -C "$repo" commit -qm initial
set +e
no_upstream_output="$(bash -c 'source "$1/dot"; update_repository "$2"' _ "$ROOT" "$repo" 2>&1)"
no_upstream_status=$?
set -e
if (( no_upstream_status == 2 )) && [[ "$no_upstream_output" == *'has no upstream'* ]] && [[ "$no_upstream_output" != *'There is no tracking information'* ]]; then
  pass 'branch without upstream gets a concise actionable warning'
else
  printf '%s\n' "$no_upstream_output" >&2
  fail_test 'branch without upstream gets a concise actionable warning'
fi
rm -rf "$repo"

fixture="$(mktemp -d)"
mkdir -p "$fixture/source/.config/example" "$fixture/home/.config/example" "$fixture/backups"
printf 'managed\n' > "$fixture/source/.config/example/settings"
printf 'local\n' > "$fixture/home/.config/example/settings"
FIXTURE="$fixture" bash -c '
  set -euo pipefail
  DOT_HOME_DIR="$FIXTURE/source"
  HOME="$FIXTURE/home"
  DOT_BACKUP_ROOT="$FIXTURE/backups"
  source "$1/scripts/lib/common.sh"
  source "$1/scripts/lib/stow.sh"
  prepare_managed_files
  test ! -e "$HOME/.config/example/settings"
  test "$(find "$DOT_BACKUP_ROOT" -type f -name settings | wc -l | tr -d " ")" = 1
' _ "$ROOT"
if [[ $? -eq 0 ]]; then
  pass 'managed home conflicts are backed up before Stow'
else
  fail_test 'managed home conflicts are backed up before Stow'
fi
rm -rf "$fixture"

if (( failures > 0 )); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'All tests passed\n'
