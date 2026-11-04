#!/usr/bin/env bash

info() {
  printf '\nRunning\n  %s\n' "$*"
}

success() {
  printf '  ✓ %s\n' "$*"
}

warn() {
  printf '  ! %s\n' "$*" >&2
}

error() {
  printf '  ✗ %s\n' "$*" >&2
}

fail() {
  error "$*"
  return 1
}

skipped() {
  printf '  - Skipped: %s\n' "$*" >&2
}

print_summary() {
  local title="$1"
  shift
  printf '\nSummary\n  %s\n' "$title"
  while (( $# > 0 )); do
    printf '  %s\n' "$1"
    shift
  done
}

print_action_required() {
  printf '\nAction required\n'
  while (( $# > 0 )); do
    printf '  %s\n' "$1"
    shift
  done
}

print_next_action() {
  printf '\nNext action\n  %s\n' "$1"
}

run_prefixed() {
  local owner="$1"
  shift
  "$@" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
    printf '  [%s] %s\n' "$owner" "$line"
  done
  return "${PIPESTATUS[0]}"
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
