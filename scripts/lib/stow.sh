#!/usr/bin/env bash

DOT_BACKUP_SESSION=""

# Top-level home/ names this platform skips (see scripts/lib/platform.sh).
home_excludes() {
  if declare -F platform_home_excludes >/dev/null; then
    platform_home_excludes
  fi
}

# Print find arguments that prune each excluded top-level home/ entry.
home_exclude_find_args() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    printf '%s\0' -path "${DOT_HOME_DIR}/${name}" -prune -o
  done < <(home_excludes)
}

# List managed directories (excluding home/ itself), skipping platform excludes.
managed_home_dirs() {
  local args=() arg
  while IFS= read -r -d '' arg; do args+=("$arg"); done < <(home_exclude_find_args)
  find "$DOT_HOME_DIR" -mindepth 1 ${args[@]+"${args[@]}"} -type d -print | LC_ALL=C sort
}

# List managed files, skipping platform excludes.
managed_home_files() {
  local args=() arg
  while IFS= read -r -d '' arg; do args+=("$arg"); done < <(home_exclude_find_args)
  find "$DOT_HOME_DIR" ${args[@]+"${args[@]}"} -type f ! -name '.DS_Store' -print | LC_ALL=C sort
}

# Stow --ignore patterns match the end of a path relative to the package, so
# anchoring with ^ limits each pattern to the top-level entry of that name.
home_exclude_stow_args() {
  local name escaped
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    escaped="$(printf '%s' "$name" | sed 's/[][\\.*^$+?(){}|\/]/\\&/g')"
    printf '%s\0' "--ignore=^${escaped}"
  done < <(home_excludes)
}

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
  done < <(managed_home_dirs)
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
  done < <(managed_home_files)
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

initialize_local_pi_config() {
  local target="${HOME}/.pi/agent/mcp.json"
  local example="${DOT_ROOT}/templates/pi/mcp.example.json"

  # Never replace existing credentials, including a dangling symlink.
  if [[ -e "$target" || -L "$target" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  (umask 077; cp "$example" "$target")
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

  local ignore_args=() arg
  while IFS= read -r -d '' arg; do ignore_args+=("$arg"); done < <(home_exclude_stow_args)

  info "Applying managed home links"
  if ! run_prefixed Stow stow --restow --no-folding --ignore='\.DS_Store' ${ignore_args[@]+"${ignore_args[@]}"} --dir "$DOT_ROOT" --target "$HOME" home; then
    error "Managed home links could not be applied; run: dot apply home"
    return 1
  fi
  sync_claude_skills
  initialize_local_pi_config
  success "Managed files point to $DOT_HOME_DIR"
  success "Shared agent skills are available to Claude Code"

  if [[ -n "$DOT_BACKUP_SESSION" ]]; then
    warn "Existing files were saved under $DOT_BACKUP_SESSION"
  fi
}
