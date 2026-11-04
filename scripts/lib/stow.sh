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
  done < <(find "$DOT_HOME_DIR" -type f ! -name '.DS_Store' | LC_ALL=C sort)
}

migrate_legacy_pi_skills() {
  local archive_all="${1:-0}"
  local source name legacy
  local legacy_skills="${HOME}/.pi/agent/skills"

  for source in "${DOT_HOME_DIR}/.agents/skills"/*/; do
    [[ -d "$source" ]] || continue
    name="$(basename "$source")"
    legacy="${legacy_skills}/${name}"
    [[ -e "$legacy" || -L "$legacy" ]] || continue

    if [[ "$archive_all" == "1" ]] || { [[ -d "$legacy" ]] && diff -qr -- "$source" "$legacy" >/dev/null 2>&1; }; then
      backup_target "$legacy"
    else
      warn "legacy Pi skill differs from shared skill; left untouched: ~/.pi/agent/skills/${name}"
      warn "Run 'dot apply home --archive-legacy-skills' to archive it and use the repo copy"
    fi
  done
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
  local archive_legacy_skills="${1:-0}"

  if ! command_exists stow; then
    error "GNU Stow is required; run: dot setup"
    return 1
  fi
  if [[ ! -d "$DOT_HOME_DIR" ]]; then
    error "Managed home tree not found: $DOT_HOME_DIR"
    return 1
  fi

  DOT_BACKUP_SESSION=""
  info "Checking managed home paths"
  migrate_legacy_pi_skills "$archive_legacy_skills"
  prepare_managed_directories
  prepare_managed_files

  info "Applying managed home links"
  if ! run_prefixed Stow stow --restow --no-folding --ignore='\.DS_Store' --dir "$DOT_ROOT" --target "$HOME" home; then
    error "Managed home links could not be applied; run: dot apply home"
    return 1
  fi
  sync_claude_skills
  success "Managed files point to $DOT_HOME_DIR"
  success "Shared agent skills are available to Claude Code"

  if [[ -n "$DOT_BACKUP_SESSION" ]]; then
    warn "Existing files were saved under $DOT_BACKUP_SESSION"
  fi
}
