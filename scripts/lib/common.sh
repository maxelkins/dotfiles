#!/usr/bin/env bash

info() {
  printf '==> %s\n' "$*"
}

success() {
  printf '  ok: %s\n' "$*"
}

warn() {
  printf '  warning: %s\n' "$*" >&2
}

fail() {
  printf '  error: %s\n' "$*" >&2
  return 1
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

link_dot_command() {
  local bin_dir="${HOME}/.local/bin"
  local target="${bin_dir}/dot"

  mkdir -p "$bin_dir"

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" && "$target" -ef "${DOT_ROOT}/dot" ]]; then
      success "dot command is already linked"
      return 0
    fi
    fail "$target already exists and is not managed by this repository"
    return 1
  fi

  ln -s "${DOT_ROOT}/dot" "$target"
  success "linked $target"
}

unlink_dot_command() {
  local target="${HOME}/.local/bin/dot"

  if [[ -L "$target" && "$target" -ef "${DOT_ROOT}/dot" ]]; then
    rm "$target"
    success "removed $target"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    fail "$target is not managed by this repository"
    return 1
  fi

  success "dot command is already unlinked"
}
