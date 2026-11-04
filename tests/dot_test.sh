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
import re
import select
import signal
import sys
import time

root = sys.argv[1]
def start(args, env=None):
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.environ['TERM'] = 'xterm-256color'
        os.environ.pop('NO_COLOR', None)
        if env:
            os.environ.update(env)
        os.execvp(args[0], args)
    return pid, master

def wait_for_exit(pid):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        # Drain terminal output so macOS can finish closing the slave PTY.
        if select.select([master], [], [], 0.01)[0]:
            try:
                os.read(master, 4096)
            except OSError:
                pass
        finished, status = os.waitpid(pid, os.WNOHANG)
        if finished:
            assert status == 0, status
            return
        time.sleep(0.01)
    raise AssertionError("Menu did not exit without Enter")

def cleanup(pid, master):
    try:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except ProcessLookupError:
        pass
    os.close(master)

pid, master = start([os.path.join(root, "dot")])
output = b""
deadline = time.time() + 5
while b"Quit\r\n\r\n" not in output and time.time() < deadline:
    readable, _, _ = select.select([master], [], [], 0.1)
    if readable:
        output += os.read(master, 4096)
try:
    os.write(master, b"q")
    wait_for_exit(pid)
finally:
    cleanup(pid, master)
if b"Dot\r\n" not in output or b"Current package profile:" not in output:
    sys.stderr.write(output.decode(errors="replace"))
    raise SystemExit(1)

assert b'\x1b[1;31m\r\nDot\r\n' in output, 'TTY title should be Dot in red'
plain = re.sub(rb'\x1b\[[0-9;]*m', b'', output)
assert b'[1] Set up this Mac' in plain
assert b'[q] Quit' in plain
assert b'Choose an operation' not in plain

# Exercise numeric choices and both submenus without sending any newlines.
script = '''
source "$1/dot"
cmd_check() { printf 'DISPATCH check\\n'; }
cmd_apply() { printf 'DISPATCH apply:%s\\n' "$*"; }
cmd_change_profile() { printf 'PROFILE %s\\n' "$1"; }
interactive_menu
'''
pid, master = start(["bash", "-c", script, "_", root])
output = b""

def expect(text):
    global output
    deadline = time.monotonic() + 3
    while text not in output:
        if time.monotonic() >= deadline:
            raise AssertionError(f"Timed out waiting for {text!r}: {output!r}")
        if select.select([master], [], [], 0.1)[0]:
            output += os.read(master, 4096)
    output = output.split(text, 1)[1]

try:
    expect(b"Quit\r\n\r\n")
    os.write(master, b"3")
    expect(b"DISPATCH check")
    expect(b"Quit\r\n\r\n")
    os.write(master, b"4")
    expect(b"Back\r\n\r\n")
    os.write(master, b"1")
    expect(b"DISPATCH apply:home")
    expect(b"Quit\r\n\r\n")
    os.write(master, b"5")
    expect(b"Back\r\n\r\n")
    os.write(master, b"3")
    expect(b"PROFILE work")
    expect(b"Quit\r\n\r\n")
    os.write(master, b"q")
    wait_for_exit(pid)
finally:
    cleanup(pid, master)

for env in ({'NO_COLOR': '1'}, {'TERM': 'dumb'}):
    pid, master = start([os.path.join(root, 'dot')], env)
    output = b''
    try:
        expect(b'Quit\r\n\r\n')
        # expect consumes matched output, so capture a second menu through a submenu.
        os.write(master, b'4')
        deadline = time.monotonic() + 3
        while b'Back\r\n\r\n' not in output:
            assert time.monotonic() < deadline, 'Missing submenu'
            if select.select([master], [], [], 0.1)[0]:
                output += os.read(master, 4096)
        assert b'\x1b[' not in output, env
        assert b'[1] Managed home links' in output
        assert b'Choose' not in output
        os.write(master, b'bq')
        wait_for_exit(pid)
    finally:
        cleanup(pid, master)
PY
  then
    pass 'TTY menus use accented bracketed keys, respect colour settings, and dispatch without Enter'
  else
    fail_test 'TTY menus dispatch single keys without Enter'
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
if [[ "$menu_output" != *$'\033['* && "$menu_output" != *'Choose an operation'* && "$menu_output" != *'Choose a profile'* ]]; then
  pass 'redirected menus have no ANSI colours or choice prompt'
else
  fail_test 'redirected menus have no ANSI colours or choice prompt'
fi
assert_contains "$menu_output" '[1] Set up this Mac' 'menu options use bracketed keys'
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
