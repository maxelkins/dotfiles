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
assert_contains "$non_tty_output" 'Usage: dot [--headless] [command]' 'no-argument non-TTY invocation prints help'

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

fixture="$(mktemp -d)"
FIXTURE="$fixture" bash -c '
  set -euo pipefail
  DOT_ROOT="$1"
  HOME="$FIXTURE/home"
  source "$1/scripts/lib/stow.sh"
  initialize_local_pi_config
  cmp "$DOT_ROOT/templates/pi/mcp.example.json" "$HOME/.pi/agent/mcp.json"
  test ! -L "$HOME/.pi/agent/mcp.json"
  printf "local credentials\n" > "$HOME/.pi/agent/mcp.json"
  initialize_local_pi_config
  test "$(<"$HOME/.pi/agent/mcp.json")" = "local credentials"
  rm "$HOME/.pi/agent/mcp.json"
  ln -s "$FIXTURE/missing" "$HOME/.pi/agent/mcp.json"
  initialize_local_pi_config
  test -L "$HOME/.pi/agent/mcp.json"
  test ! -e "$FIXTURE/missing"
' _ "$ROOT"
pass 'local MCP config is seeded without replacing existing files or symlinks'
rm -rf "$fixture"

unsupported_home="$(mktemp -d)"
hooks_before="$(git -C "$ROOT" config core.hooksPath || true)"
set +e
unsupported_output="$(HOME="$unsupported_home" DOT_PLATFORM=unsupported "$ROOT/dot" setup work 2>&1)"
unsupported_status=$?
set -e
hooks_after="$(git -C "$ROOT" config core.hooksPath || true)"
if (( unsupported_status != 0 )) && [[ -z "$(find "$unsupported_home" -mindepth 1 -print -quit)" && "$hooks_before" == "$hooks_after" ]]; then
  pass 'setup on an unsupported platform fails without changes'
else
  printf '%s\n' "$unsupported_output" >&2
  fail_test 'setup on an unsupported platform fails without changes'
fi
assert_contains "$unsupported_output" 'unsupported platform' 'setup names the unsupported platform'
assert_contains "$unsupported_output" 'Setup failed before changes were made' 'unsupported setup reports that nothing changed'
for command in check upgrade; do
  set +e
  unsupported_output="$(HOME="$unsupported_home" DOT_PLATFORM=missing-backend "$ROOT/dot" "$command" 2>&1)"
  unsupported_status=$?
  set -e
  if (( unsupported_status != 0 )) && [[ "$unsupported_output" == *'unsupported platform: missing-backend'* ]]; then
    pass "$command fails cleanly without a platform backend"
  else
    printf '%s\n' "$unsupported_output" >&2
    fail_test "$command fails cleanly without a platform backend"
  fi
done
unsupported_menu="$(HOME="$unsupported_home" DOT_PLATFORM=unsupported bash -c 'source "$1/dot"; interactive_menu' _ "$ROOT" <<< 'q' 2>&1)"
assert_contains "$unsupported_menu" '[1] Set up this machine' 'menu uses a generic label without a platform backend'
rm -rf "$unsupported_home"

platform_name="$(DOT_PLATFORM=linux bash -c 'DOT_ROOT="$1"; source "$1/scripts/lib/common.sh"; source "$1/scripts/lib/platform.sh"; dot_platform' _ "$ROOT")"
if [[ "$platform_name" == linux ]]; then
  pass 'DOT_PLATFORM overrides platform detection'
else
  fail_test 'DOT_PLATFORM overrides platform detection'
fi

fixture="$(mktemp -d)"
mkdir -p "$fixture/repo/home/Library/App" "$fixture/repo/home/.config/Library" "$fixture/repo/templates/pi" "$fixture/home"
printf 'mac only\n' > "$fixture/repo/home/Library/App/config"
printf 'nested\n' > "$fixture/repo/home/.config/Library/config"
printf '{}\n' > "$fixture/repo/templates/pi/mcp.example.json"
set +e
exclude_output="$(FIXTURE="$fixture" bash -c '
  set -euo pipefail
  DOT_ROOT="$FIXTURE/repo"
  DOT_HOME_DIR="$DOT_ROOT/home"
  HOME="$FIXTURE/home"
  DOT_BACKUP_ROOT="$FIXTURE/backups"
  source "$1/scripts/lib/common.sh"
  source "$1/scripts/lib/profile.sh"
  source "$1/scripts/lib/stow.sh"
  source "$1/scripts/lib/steps.sh"
  source "$1/scripts/lib/doctor.sh"
  platform_home_excludes() { printf "Library\n"; }
  platform_skips_step() { return 1; }
  DOT_STEPS=("home links | check_managed_links | install_home_links | - | - | yes | Repair managed links: dot apply home")

  test "$(managed_home_files)" = "$DOT_HOME_DIR/.config/Library/config"
  prepare_managed_directories
  test ! -e "$HOME/Library"
  test -d "$HOME/.config/Library"
  if command -v stow >/dev/null 2>&1; then
    stow_home >/dev/null 2>&1
    test ! -e "$HOME/Library"
    test "$HOME/.config/Library/config" -ef "$DOT_HOME_DIR/.config/Library/config"
  else
    ln -s "$DOT_HOME_DIR/.config/Library/config" "$HOME/.config/Library/config"
  fi
  run_doctor
' _ "$ROOT" 2>&1)"
exclude_status=$?
set -e
if (( exclude_status == 0 )) && [[ "$exclude_output" == *'1 managed links are correct'* ]]; then
  pass 'stow and doctor skip only top-level platform_home_excludes'
else
  printf '%s\n' "$exclude_output" >&2
  fail_test 'stow and doctor skip only top-level platform_home_excludes'
fi
rm -rf "$fixture"

for backend in macos linux; do
  set +e
  backend_output="$(DOT_PLATFORM="$backend" bash -c '
    source "$1/dot"
    (( DOT_PLATFORM_BACKEND_LOADED == 1 )) || { echo "backend not loaded"; exit 1; }
    seen="|"
    for row in "${DOT_STEPS[@]}"; do
      step_parse "$row"
      for fn in "$STEP_CHECK" "$STEP_INSTALL" "$STEP_UPGRADE"; do
        [[ "$fn" == skip ]] || declare -F "$fn" >/dev/null || echo "$STEP_NAME: $fn is not defined"
      done
      [[ "$STEP_REQUIRED" == yes || "$STEP_REQUIRED" == no ]] || echo "$STEP_NAME: required must be yes or no"
      [[ -n "$STEP_ACTION" ]] || echo "$STEP_NAME: action is empty"
      [[ "$STEP_NEEDS" == - || "$seen" == *"|$STEP_NEEDS|"* ]] || echo "$STEP_NAME: needs unknown or later step $STEP_NEEDS"
      seen+="$STEP_NAME|"
    done
  ' _ "$ROOT" 2>&1)"
  set -e
  if [[ -z "$backend_output" ]]; then
    pass "every step row has defined check and install functions on $backend"
  else
    printf '%s\n' "$backend_output" >&2
    fail_test "every step row has defined check and install functions on $backend"
  fi
done

# Replace every function named in the step table with a recorder, then run
# setup, upgrade, and doctor in a scratch HOME.
step_home="$(mktemp -d)"
set +e
step_output="$(HOME="$step_home" DOT_PLATFORM=macos bash -c '
  source "$1/dot"
  for row in "${DOT_STEPS[@]}"; do
    step_parse "$row"
    for fn in "$STEP_CHECK" "$STEP_INSTALL" "$STEP_UPGRADE"; do
      [[ "$fn" == skip ]] && continue
      eval "$fn() { printf \"CALL %s\\n\" \"\$FUNCNAME\" >>\"\$HOME/calls\"; }"
    done
  done
  cmd_setup base >/dev/null 2>&1 || exit 1
  mv "$HOME/calls" "$HOME/setup.calls"
  run_doctor >/dev/null 2>&1 || exit 1
  mv "$HOME/calls" "$HOME/check.calls"
  for row in "${DOT_STEPS[@]}"; do
    step_parse "$row"
    printf "%s\t%s\t%s\n" "$STEP_NAME" "$STEP_INSTALL" "$STEP_CHECK"
  done
' _ "$ROOT" 2>&1)"
step_status=$?
set -e
if (( step_status == 0 )); then
  expected_setup="" expected_check=""
  while IFS=$'\t' read -r step_name step_install step_check; do
    expected_setup+="CALL ${step_install}"$'\n'
    expected_check+="CALL ${step_check}"$'\n'
  done <<<"$step_output"
  if [[ "$(<"$step_home/setup.calls")"$'\n' == "$expected_setup" && "$(<"$step_home/check.calls")"$'\n' == "$expected_check" ]]; then
    pass 'setup and doctor iterate the same step rows in order'
  else
    printf 'setup:\n%s\ncheck:\n%s\n' "$(<"$step_home/setup.calls")" "$(<"$step_home/check.calls")" >&2
    fail_test 'setup and doctor iterate the same step rows in order'
  fi
else
  printf '%s\n' "$step_output" >&2
  fail_test 'setup and doctor iterate the same step rows in order'
fi
rm -rf "$step_home"

set +e
doctor_output="$(DOT_PLATFORM=macos bash -c '
  source "$1/dot"
  ok() { success "fine"; }
  bad() { warn "broken"; return 1; }
  DOT_STEPS=(
    "one   | bad | ok | - | - | yes | Fix it: dot setup"
    "two   | ok  | ok | - | - | yes | Other: dot upgrade"
    "three | bad | ok | - | - | yes | Fix it: dot setup"
    "four  | bad | ok | - | - | no  | Optional: dot setup"
  )
  run_doctor
' _ "$ROOT" 2>&1)"
doctor_status=$?
set -e
fix_count="$(grep -c 'Fix it: dot setup' <<<"$doctor_output" || true)"
if (( doctor_status != 0 )) && [[ "$fix_count" == 1 && "$doctor_output" == *'2 health check(s) failed'* && "$doctor_output" == *'Optional: dot setup'* && "$doctor_output" != *'Other: dot upgrade'* ]]; then
  pass 'doctor counts required failures and lists each failed action once'
else
  printf '%s\n' "$doctor_output" >&2
  fail_test 'doctor counts required failures and lists each failed action once'
fi

set +e
gate_output="$(DOT_PLATFORM=macos bash -c '
  source "$1/dot"
  ok() { printf "RAN %s\n" "$FUNCNAME"; }
  prep() { printf "RAN prep\n"; return 1; }
  pkgs() { printf "RAN pkgs\n"; }
  later() { printf "RAN later\n"; }
  DOT_STEPS=(
    "prerequisites | ok | prep  | skip | -             | yes | a"
    "packages      | ok | pkgs  | -    | prerequisites | yes | b"
    "later         | ok | later | -    | -             | yes | c"
  )
  run_steps install || true
  printf "FAILURES %s\n" "$DOT_STEP_FAILURES"
  run_steps upgrade
' _ "$ROOT" 2>&1)"
set -e
if [[ "$gate_output" == $'RAN prep\nRAN later\nFAILURES 1\nRAN pkgs\nRAN later' ]]; then
  pass 'a failed step skips dependants, later steps continue, and upgrade honours skip'
else
  printf '%s\n' "$gate_output" >&2
  fail_test 'a failed step skips dependants, later steps continue, and upgrade honours skip'
fi

# Headless mode.
# shellcheck disable=SC2016 # expanded by the child bash
headless_env_script='
  source "$1/dot"
  dispatch_command() {
    printf "%s\n" "DOT_HEADLESS=${DOT_HEADLESS-}" "DEBIAN_FRONTEND=${DEBIAN_FRONTEND-}" \
      "NEEDRESTART_MODE=${NEEDRESTART_MODE-}" "NONINTERACTIVE=${NONINTERACTIVE-}" \
      "GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-}" "GIT_SSH_COMMAND=${GIT_SSH_COMMAND-}" "ARGS=$*"
    bash -c "printf \"child:%s\n\" \"\$DOT_HEADLESS:\$DEBIAN_FRONTEND:\$NONINTERACTIVE:\$GIT_TERMINAL_PROMPT\""
  }
  main "${@:2}"
'
headless_expected='DOT_HEADLESS=1
DEBIAN_FRONTEND=noninteractive
NEEDRESTART_MODE=a
NONINTERACTIVE=1
GIT_TERMINAL_PROMPT=0
GIT_SSH_COMMAND=ssh -o BatchMode=yes
ARGS=check
child:1:noninteractive:1:0'
clean_env=(env -u DOT_HEADLESS -u DEBIAN_FRONTEND -u NEEDRESTART_MODE -u NONINTERACTIVE -u GIT_TERMINAL_PROMPT -u GIT_SSH_COMMAND -u GIT_SSH)
for variant in flag env; do
  if [[ "$variant" == flag ]]; then
    headless_output="$("${clean_env[@]}" bash -c "$headless_env_script" _ "$ROOT" --headless check </dev/null 2>&1)"
  else
    headless_output="$("${clean_env[@]}" DOT_HEADLESS=1 bash -c "$headless_env_script" _ "$ROOT" check </dev/null 2>&1)"
  fi
  if [[ "$headless_output" == "$headless_expected" ]]; then
    pass "headless $variant exports the no-prompt variables to child processes"
  else
    printf 'Expected:\n%s\nGot:\n%s\n' "$headless_expected" "$headless_output" >&2
    fail_test "headless $variant exports the no-prompt variables to child processes"
  fi
done
headless_output="$("${clean_env[@]}" GIT_SSH_COMMAND='ssh -i key' bash -c "$headless_env_script" _ "$ROOT" --headless check </dev/null 2>&1)"
assert_contains "$headless_output" 'GIT_SSH_COMMAND=ssh -i key' 'headless keeps a caller-provided GIT_SSH_COMMAND'
headless_output="$("${clean_env[@]}" bash -c "$headless_env_script" _ "$ROOT" check </dev/null 2>&1)"
if [[ "$headless_output" == *'DOT_HEADLESS=0'* && "$headless_output" == *$'DEBIAN_FRONTEND=\n'* && "$headless_output" == *$'GIT_TERMINAL_PROMPT=\n'* ]]; then
  pass 'without headless, the no-prompt variables are left alone'
else
  printf '%s\n' "$headless_output" >&2
  fail_test 'without headless, the no-prompt variables are left alone'
fi

set +e
headless_output="$(DOT_HEADLESS=maybe "$ROOT/dot" help 2>&1)"
headless_status=$?
set -e
if (( headless_status != 0 )) && [[ "$headless_output" == *'DOT_HEADLESS must be 1 or 0'* ]]; then
  pass 'an unrecognised DOT_HEADLESS value is rejected'
else
  printf '%s\n' "$headless_output" >&2
  fail_test 'an unrecognised DOT_HEADLESS value is rejected'
fi

set +e
headless_output="$("$ROOT/dot" --bogus setup 2>&1)"
headless_status=$?
set -e
if (( headless_status != 0 )) && [[ "$headless_output" == *'Unknown global option: --bogus'* ]]; then
  pass 'an unknown global option is rejected'
else
  printf '%s\n' "$headless_output" >&2
  fail_test 'an unknown global option is rejected'
fi

headless_output="$("$ROOT/dot" --headless </dev/null 2>&1)"
assert_contains "$headless_output" 'Usage: dot [--headless] [command]' 'dot --headless without a command prints help'
assert_contains "$("$ROOT/dot" --headless --help 2>&1)" 'DOT_HEADLESS=1' 'help documents headless mode'

profile_home="$(mktemp -d)"
mkdir -p "$profile_home/.config/mac-setup"
printf 'work\n' >"$profile_home/.config/mac-setup/profile"
headless_output="$(HOME="$profile_home" bash -c 'source "$1/dot"; DOT_HEADLESS=1; choose_profile_for_setup' _ "$ROOT" </dev/null 2>&1)"
if [[ "$headless_output" == work ]]; then
  pass 'headless profile chooser takes the saved default without a prompt'
else
  printf '%s\n' "$headless_output" >&2
  fail_test 'headless profile chooser takes the saved default without a prompt'
fi

# The same at a real terminal, as with `ssh -t`: nothing may wait for input.
if command -v python3 >/dev/null 2>&1; then
  if python3 - "$ROOT" "$profile_home" <<'PY'
import os
import pty
import select
import sys
import time

root, home = sys.argv[1], sys.argv[2]

def run(args, env):
    pid, master = pty.fork()
    if pid == 0:
        os.environ.update(env)
        os.environ['TERM'] = 'dumb'
        os.execvp(args[0], args)
    output = b''
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if select.select([master], [], [], 0.05)[0]:
            try:
                output += os.read(master, 4096)
            except OSError:
                pass
        finished, status = os.waitpid(pid, os.WNOHANG)
        if finished:
            try:
                while select.select([master], [], [], 0.05)[0]:
                    chunk = os.read(master, 4096)
                    if not chunk:
                        break
                    output += chunk
            except OSError:
                pass
            os.close(master)
            return status, output.decode(errors='replace')
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    os.close(master)
    raise AssertionError(f'{args} waited for input at a terminal: {output!r}')

status, out = run([os.path.join(root, 'dot'), '--headless'], {})
assert status == 0 and 'Usage: dot' in out and 'Quit' not in out, out

status, out = run([os.path.join(root, 'dot')], {'DOT_HEADLESS': '1'})
assert status == 0 and 'Usage: dot' in out and 'Quit' not in out, out

script = 'source "$1/dot"; DOT_HEADLESS=1; choose_profile_for_setup'
status, out = run(['bash', '-c', script, '_', root], {'HOME': home})
assert status == 0 and out.strip() == 'work' and 'Package profile [' not in out, out
PY
  then
    pass 'headless mode at a terminal prints help and takes the profile default without waiting'
  else
    fail_test 'headless mode at a terminal prints help and takes the profile default without waiting'
  fi
fi
rm -rf "$profile_home"

sudo_output="$(bash -c '
  DOT_ROOT="$1"
  source "$1/scripts/lib/common.sh"
  source "$1/scripts/lib/platform/linux.sh"
  sudo() { [[ "$1" == -n ]] || { echo "sudo prompted" >&2; return 0; }; return 1; }
  DOT_HEADLESS=1
  if linux_check_sudo; then echo "unexpected success"; fi
  DOT_HEADLESS=0
  if linux_check_sudo </dev/null; then echo "unexpected success"; fi
' _ "$ROOT" 2>&1)"
if [[ "$sudo_output" == *'sudo needs a password; configure passwordless sudo for unattended runs or run without --headless'* &&
  "$sudo_output" == *'or run dot from a terminal'* &&
  "$sudo_output" != *'sudo prompted'* && "$sudo_output" != *'unexpected success'* ]]; then
  pass 'Linux sudo check fails fast without prompting when not interactive'
else
  printf '%s\n' "$sudo_output" >&2
  fail_test 'Linux sudo check fails fast without prompting when not interactive'
fi

# Linux release binaries from packages/extras.linux.
extras_output="$(bash -c '
  set -euo pipefail
  DOT_ROOT="$1"
  source "$1/scripts/lib/common.sh"
  source "$1/scripts/lib/platform/linux.sh"
  linux_extras_names
  for machine in x86_64 aarch64; do
    uname() { printf "%s\n" "$machine"; }
    arch="$(linux_extras_arch)"
    printf "%s %s %s\n" "$arch" "$(linux_extra_field asdf url)" "$(linux_extra_field asdf "sha256.$arch")"
  done
  printf "%s|%s|%s\n" "$(linux_extra_field asdf binary)" "$(linux_extra_field asdf check)" "$(linux_extra_field asdf expect)"
' _ "$ROOT" 2>&1)"
extras_expected='asdf
amd64 https://github.com/asdf-vm/asdf/releases/download/v0.20.2/asdf-v0.20.2-linux-amd64.tar.gz 6d45e6fab12f50a259b5643adf06a2e77af30a87300b4402440eda09af467a6d
arm64 https://github.com/asdf-vm/asdf/releases/download/v0.20.2/asdf-v0.20.2-linux-arm64.tar.gz 356e135a608bdfba34038c1f18c4b82434d7b6d546e30dbf372c61baaa2f442c
asdf|version|v0.20.2'
if [[ "$extras_output" == "$extras_expected" ]]; then
  pass 'extras table resolves the pinned asdf release for each architecture'
else
  printf 'Expected:\n%s\nGot:\n%s\n' "$extras_expected" "$extras_output" >&2
  fail_test 'extras table resolves the pinned asdf release for each architecture'
fi

if command -v sha256sum >/dev/null 2>&1; then
  fixture="$(mktemp -d)"
  mkdir -p "$fixture/repo/packages" "$fixture/home" "$fixture/tmp" "$fixture/src/demo-1.2.3-x86_64/bin"
  printf '#!/bin/sh\necho "demo 1.2.3 (build abc)"\n' >"$fixture/src/demo-1.2.3-x86_64/bin/demo"
  chmod +x "$fixture/src/demo-1.2.3-x86_64/bin/demo"
  tar -czf "$fixture/demo.tar.gz" -C "$fixture/src" demo-1.2.3-x86_64
  demo_sha="$(sha256sum "$fixture/demo.tar.gz")"
  demo_sha="${demo_sha%% *}"
  write_demo_table() {
    cat >"$fixture/repo/packages/extras.linux" <<TABLE
# fixture
[demo]
version      = $1
url          = https://example.invalid/demo/{version}/demo-{arch}.tgz
binary       = demo-{version}-{arch}/bin/demo
check        = --version
expect       = {version}
arch         = amd64=x86_64 arm64=aarch64
sha256.amd64 = $2
sha256.arm64 = $2
TABLE
  }
  run_demo() {
    FIXTURE="$fixture" TMPDIR="$fixture/tmp" bash -c '
      DOT_ROOT="$FIXTURE/repo"
      HOME="$FIXTURE/home"
      source "$1/scripts/lib/common.sh"
      source "$1/scripts/lib/platform/linux.sh"
      uname() { printf "x86_64\n"; }
      curl() {
        local out="" url=""
        while (( $# > 0 )); do
          case "$1" in -o) out="$2"; shift ;; https://*) url="$1" ;; esac
          shift
        done
        printf "%s\n" "$url" >>"$FIXTURE/downloads"
        cp "$FIXTURE/demo.tar.gz" "$out"
      }
      "${@:2}"
    ' _ "$ROOT" "$@" 2>&1
  }

  write_demo_table 1.2.3 "$demo_sha"
  set +e
  extras_check_missing="$(run_demo linux_check_extras)"
  extras_check_missing_status=$?
  extras_first="$(run_demo linux_install_extras)"
  extras_first_status=$?
  extras_first_downloads="$(<"$fixture/downloads")"
  extras_second="$(run_demo linux_install_extras)"
  extras_second_status=$?
  extras_second_downloads="$(<"$fixture/downloads")"
  extras_check_ok="$(run_demo linux_check_extras)"
  extras_check_ok_status=$?
  write_demo_table 1.2.30 "$demo_sha"
  extras_check_old="$(run_demo linux_check_extras)"
  extras_check_old_status=$?
  write_demo_table 1.2.4 "$(printf '0%.0s' {1..64})"
  extras_bad_sum="$(run_demo linux_install_extras)"
  extras_bad_sum_status=$?
  set -e

  if (( extras_check_missing_status == 1 )) && [[ "$extras_check_missing" == *'Release binary demo 1.2.3 is not installed'* ]]; then
    pass 'extras check reports a missing release binary'
  else
    printf '%s\n' "$extras_check_missing" >&2
    fail_test 'extras check reports a missing release binary'
  fi
  if (( extras_first_status == 0 )) && [[ "$extras_first" == *'Installed demo 1.2.3'* ]] &&
    [[ "$extras_first_downloads" == 'https://example.invalid/demo/1.2.3/demo-x86_64.tgz' ]] &&
    [[ -x "$fixture/home/.local/bin/demo" ]]; then
    pass 'extras install expands {version} and a per-tool arch map, verifies, and installs'
  else
    printf '%s\n' "$extras_first" >&2
    fail_test 'extras install expands {version} and a per-tool arch map, verifies, and installs'
  fi
  if (( extras_second_status == 0 )) && [[ "$extras_second" == *'demo 1.2.3 is already installed'* ]] &&
    [[ "$extras_second_downloads" == "$extras_first_downloads" ]]; then
    pass 'extras install is idempotent and skips the download'
  else
    printf '%s\n' "$extras_second" >&2
    fail_test 'extras install is idempotent and skips the download'
  fi
  if (( extras_check_ok_status == 0 && extras_check_old_status == 1 )) &&
    [[ "$extras_check_old" == *'Release binary demo is outdated: want 1.2.30, found: demo 1.2.3 (build abc)'* ]]; then
    pass 'extras check compares versions exactly'
  else
    printf '%s\n%s\n' "$extras_check_ok" "$extras_check_old" >&2
    fail_test 'extras check compares versions exactly'
  fi
  if (( extras_bad_sum_status != 0 )) && [[ "$extras_bad_sum" == *'demo checksum mismatch'* ]] &&
    [[ "$("$fixture/home/.local/bin/demo")" == 'demo 1.2.3 (build abc)' ]] &&
    [[ -z "$(find "$fixture/tmp" -mindepth 1 -print -quit)" ]]; then
    pass 'extras install rejects a checksum mismatch and cleans up its temporary files'
  else
    printf '%s\n' "$extras_bad_sum" >&2
    fail_test 'extras install rejects a checksum mismatch and cleans up its temporary files'
  fi
  rm -rf "$fixture"
fi

if (( failures > 0 )); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'All tests passed\n'
