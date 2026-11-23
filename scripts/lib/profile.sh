#!/usr/bin/env bash

profile_file() {
  printf '%s/mac-setup/profile\n' "${XDG_CONFIG_HOME:-${HOME}/.config}"
}

validate_profile() {
  case "$1" in
    base|personal|work) return 0 ;;
    *) fail "profile must be base, personal, or work" ;;
  esac
}

current_profile() {
  local file
  file="$(profile_file)"

  if [[ ! -f "$file" ]]; then
    printf 'base\n'
    return 0
  fi

  local profile
  IFS= read -r profile < "$file"
  validate_profile "$profile" >/dev/null
  printf '%s\n' "$profile"
}

save_profile() {
  local profile="$1"
  local file
  validate_profile "$profile"
  file="$(profile_file)"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$profile" > "$file"
  success "Saved package profile: $profile"
}

choose_profile_for_setup() {
  local requested="${1:-}"

  if [[ -n "$requested" ]]; then
    validate_profile "$requested"
    printf '%s\n' "$requested"
    return 0
  fi

  local default_profile="base"
  if [[ -f "$(profile_file)" ]]; then
    default_profile="$(current_profile)"
  fi

  if ! dot_interactive; then
    printf '%s\n' "$default_profile"
    return 0
  fi

  local choice
  printf 'Package profile [base/personal/work] (%s): ' "$default_profile" >&2
  IFS= read -r choice
  choice="${choice:-$default_profile}"
  validate_profile "$choice"
  printf '%s\n' "$choice"
}
