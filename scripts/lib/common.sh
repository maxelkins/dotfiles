#!/usr/bin/env bash

# Accent terminal output only; respect https://no-color.org/ and dumb terminals.
styled_printf() {
  local style="$1"
  shift
  if [[ -t 1 && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm' "$style"
    printf "$@"
    printf '\033[0m'
  else
    printf "$@"
  fi
}

print_menu_heading() {
  styled_printf '1;36' '\n%s\n\n' "$1"
}

print_menu_option() {
  styled_printf '36' '[%s]' "$1"
  printf ' %s\n' "$2"
}

info() {
  styled_printf '1;36' '\nRunning\n'
  printf '  %s\n' "$*"
}

success() {
  styled_printf '32' '  ✓ %s\n' "$*"
}

warn() {
  styled_printf '33' '  ! %s\n' "$*" >&2
}

error() {
  styled_printf '31' '  ✗ %s\n' "$*" >&2
}

fail() {
  error "$*"
  return 1
}

skipped() {
  styled_printf '2' '  - Skipped: %s\n' "$*" >&2
}

print_summary() {
  local title="$1"
  shift
  styled_printf '1;36' '\nSummary\n'
  printf '  %s\n' "$title"
  while (( $# > 0 )); do
    printf '  %s\n' "$1"
    shift
  done
}

print_action_required() {
  styled_printf '1;33' '\nAction required\n'
  while (( $# > 0 )); do
    printf '  %s\n' "$1"
    shift
  done
}

print_next_action() {
  styled_printf '1;36' '\nNext action\n'
  printf '  %s\n' "$1"
}

run_prefixed() {
  local owner="$1"
  shift
  "$@" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
    printf '  [%s] %s\n' "$owner" "$line"
  done
  return "${PIPESTATUS[0]}"
}

# Read a single key at a terminal, but retain line input for scripts and tests.
read_menu_choice() {
  if [[ -t 0 ]]; then
    IFS= read -r -s -n 1 "$1" || return 1
    printf '\n'
  else
    IFS= read -r "$1"
  fi
}

# Headless mode (dot --headless or DOT_HEADLESS=1) is for unattended runs such
# as provisioning scripts and SSH sessions: nothing may wait for an answer,
# even when `ssh -t` provides a terminal.
dot_headless() {
  [[ "${DOT_HEADLESS:-}" == 1 ]]
}

# Normalise DOT_HEADLESS and, when it is on, export the variables that stop
# the tools dot runs from prompting. Fails on an unrecognised value.
dot_configure_headless() {
  case "${DOT_HEADLESS:-}" in
    '' | 0 | false | no)
      DOT_HEADLESS=0
      return 0
      ;;
    1 | true | yes) ;;
    *)
      fail "DOT_HEADLESS must be 1 or 0, not '${DOT_HEADLESS}'"
      return 1
      ;;
  esac

  # apt/debconf and needrestart (Ubuntu), the Homebrew installer, and Git
  # credential prompts for HTTPS remotes.
  export DOT_HEADLESS=1 \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=a \
    NONINTERACTIVE=1 \
    GIT_TERMINAL_PROMPT=0
  # SSH remotes: fail instead of asking for a passphrase or host key approval.
  # Respect an SSH command the caller already chose.
  if [[ -z "${GIT_SSH_COMMAND:-}" && -z "${GIT_SSH:-}" ]]; then
    export GIT_SSH_COMMAND='ssh -o BatchMode=yes'
  fi
}

# True only when dot may ask a question: not headless and stdin is a terminal.
# Every prompt must check this first and fall back to a default or fail.
dot_interactive() {
  ! dot_headless && [[ -t 0 ]]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_no_args() {
  local command_name="$1"
  shift

  if (( $# > 0 )); then
    fail "'$command_name' does not accept arguments"
  fi
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "this command supports macOS only"
  fi
}

configure_git_hooks() {
  info "Configuring repository hooks"
  if run_prefixed Git git -C "$DOT_ROOT" config core.hooksPath .githooks; then
    success "Repository hooks are configured"
  else
    error "Repository hooks could not be configured"
    return 1
  fi
}

repository_is_clean() {
  [[ -z "$(git -C "$1" status --porcelain)" ]]
}

update_repository() {
  local root="${1:-$DOT_ROOT}"
  local branch upstream

  branch="$(git -C "$root" branch --show-current)"
  if ! upstream="$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
    warn "Repository update skipped: branch '${branch:-detached HEAD}' has no upstream"
    printf '  Configure one with: git -C %q push -u origin %q\n' "$root" "${branch:-<branch>}" >&2
    return 2
  fi

  info "Updating repository from $upstream"
  if run_prefixed Git git -C "$root" pull --ff-only; then
    success "Repository is up to date"
  else
    error "Repository update failed; resolve the Git error, then run: dot upgrade"
    return 1
  fi
}

link_dot_command() {
  local bin_dir="${HOME}/.local/bin"
  local target="${bin_dir}/dot"

  info "Linking the dot command"
  mkdir -p "$bin_dir"

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" && "$target" -ef "${DOT_ROOT}/dot" ]]; then
      success "dot command is already linked"
      return 0
    fi
    error "$target already exists and is not managed by this repository"
    return 1
  fi

  ln -s "${DOT_ROOT}/dot" "$target"
  success "Linked $target"
}

unlink_dot_command() {
  local target="${HOME}/.local/bin/dot"

  if [[ -L "$target" && "$target" -ef "${DOT_ROOT}/dot" ]]; then
    rm "$target"
    success "removed $target"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    error "$target is not managed by this repository"
    return 1
  fi

  success "dot command is already unlinked"
}
