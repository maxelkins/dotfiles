#!/usr/bin/env bash

DOT_BACKUP_SESSION=""

managed_target_matches() {
  local source="$1"
  local target="$2"
  [[ -e "$target" && "$target" -ef "$source" ]]
}

ensure_backup_session() {
  if [[ -n "$DOT_BACKUP_SESSION" ]]; then
    return 0
  fi

  local backup_base="${DOT_BACKUP_ROOT:-${HOME}/.local/state/mac-setup/backups}"
  DOT_BACKUP_SESSION="${backup_base}/$(date +%Y%m%d-%H%M%S)-$$"
}

backup_target() {
  local target="$1"
  local relative="${target#${HOME}/}"

  ensure_backup_session
  local destination="${DOT_BACKUP_SESSION}/home/${relative}"
  mkdir -p "$(dirname "$destination")"
  mv "$target" "$destination"
  warn "backed up ~/${relative}"
}

prepare_managed_directories() {
  local source relative target

  while IFS= read -r source; do
    relative="${source#${DOT_HOME_DIR}/}"
    target="${HOME}/${relative}"

    if managed_target_matches "$source" "$target"; then
      continue
    fi

    if [[ -L "$target" || ( -e "$target" && ! -d "$target" ) ]]; then
      backup_target "$target"
    fi

    mkdir -p "$target"
  done < <(find "$DOT_HOME_DIR" -mindepth 1 -type d | LC_ALL=C sort)
}

prepare_managed_files() {
  local source relative target

  while IFS= read -r source; do
    relative="${source#${DOT_HOME_DIR}/}"
    target="${HOME}/${relative}"

    if managed_target_matches "$source" "$target"; then
      continue
    fi

    mkdir -p "$(dirname "$target")"
    if [[ -e "$target" || -L "$target" ]]; then
      backup_target "$target"
    fi
  done < <(find "$DOT_HOME_DIR" -type f | LC_ALL=C sort)
}

sync_claude_skills() {
  local source name target
  local claude_skills="${HOME}/.claude/skills"

  mkdir -p "$claude_skills"
  for source in "${DOT_HOME_DIR}/.agents/skills"/*/; do
    [[ -d "$source" ]] || continue
    name="$(basename "$source")"
    target="${claude_skills}/${name}"

    # A real directory belongs to Claude Code and is left untouched.
    if [[ -e "$target" && ! -L "$target" ]]; then
      continue
    fi

    ln -sfn "../../.agents/skills/${name}" "$target"
  done
}

stow_home() {
  command_exists stow || fail "GNU Stow is required; run './dot packages install'"
  [[ -d "$DOT_HOME_DIR" ]] || fail "managed home tree not found: $DOT_HOME_DIR"

  DOT_BACKUP_SESSION=""
  info "Checking managed paths"
  prepare_managed_directories
  prepare_managed_files

  info "Stowing home directory"
  stow --restow --no-folding --dir "$DOT_ROOT" --target "$HOME" home
  sync_claude_skills
  success "managed files now point to $DOT_HOME_DIR"
  success "shared agent skills are available to Claude Code"

  if [[ -n "$DOT_BACKUP_SESSION" ]]; then
    warn "existing files were saved under $DOT_BACKUP_SESSION"
  fi
}
