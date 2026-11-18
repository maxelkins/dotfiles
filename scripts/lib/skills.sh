#!/usr/bin/env bash

cmd_skills() {
  if [[ "${1:-}" != update || $# != 1 ]]; then
    error "Usage: dot skills update"
    return 1
  fi
  command_exists python3 || { error "python3 is required to update skills"; return 1; }
  command_exists git || { error "git is required to update skills"; return 1; }
  local result=0
  info "Updating repository-managed skills"
  python3 "${DOT_ROOT}/scripts/lib/skills.py" "$DOT_ROOT" || result=1
  stow_home || result=1
  print_next_action "Review git diff, commit the updates, then run /reload in Pi"
  return "$result"
}
