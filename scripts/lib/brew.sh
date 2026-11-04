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

  if [[ ! -t 0 ]]; then
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

load_brew_environment() {
  if command_exists brew; then
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_homebrew() {
  require_macos
  load_brew_environment

  if command_exists brew; then
    success "Homebrew is installed"
    return 0
  fi

  info "Installing Homebrew"
  if run_prefixed Homebrew env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    load_brew_environment
    if ! command_exists brew; then
      error "Homebrew installed but is unavailable in PATH"
      return 1
    fi
    success "Homebrew is installed"
  else
    error "Homebrew installation failed; run: dot setup"
    return 1
  fi
}

trust_declared_formulae() {
  local trust_file="${DOT_ROOT}/packages/trusted-formulae"
  local formula

  [[ -f "$trust_file" ]] || return 0

  while IFS= read -r formula; do
    [[ -n "$formula" && "$formula" != \#* ]] || continue
    if ! run_prefixed Homebrew brew trust --formula "$formula"; then
      error "Could not trust formula: $formula"
      return 1
    fi
  done < "$trust_file"
}

package_bundles() {
  local profile="$1"
  printf '%s\n' "${DOT_ROOT}/packages/bundle"
  if [[ "$profile" != "base" ]]; then
    printf '%s\n' "${DOT_ROOT}/packages/bundle.${profile}"
  fi
}

install_packages() {
  local profile bundle failed=0
  profile="$(current_profile)"

  if ! command_exists brew; then
    error "Homebrew is required; run: dot setup"
    return 1
  fi
  trust_declared_formulae || return 1
  info "Installing and upgrading the $profile package profile"

  while IFS= read -r bundle; do
    [[ -f "$bundle" ]] || { fail "Package bundle not found: $bundle"; return 1; }
    if run_prefixed Homebrew brew bundle --file="$bundle"; then
      success "$(basename "$bundle") is reconciled"
    else
      warn "$(basename "$bundle") had package failures"
      failed=1
    fi
  done < <(package_bundles "$profile")

  return "$failed"
}

check_packages() {
  local profile bundle failed=0
  profile="$(current_profile)"

  if ! command_exists brew; then
    error "Homebrew is required; run: dot setup"
    return 1
  fi

  while IFS= read -r bundle; do
    [[ -f "$bundle" ]] || { fail "Package bundle not found: $bundle"; return 1; }
    if ! run_prefixed Homebrew brew bundle check --verbose --no-upgrade --file="$bundle"; then
      failed=1
    fi
  done < <(package_bundles "$profile")

  return "$failed"
}

update_packages() {
  if ! command_exists brew; then
    error "Homebrew is required; run: dot setup"
    skipped "Homebrew metadata and package updates require Homebrew"
    return 1
  fi

  info "Updating Homebrew metadata"
  if run_prefixed Homebrew brew update; then
    success "Homebrew metadata is current"
  else
    error "Homebrew metadata update failed; run: dot upgrade"
    skipped "Package reconciliation requires current Homebrew metadata"
    return 1
  fi
  install_packages
}
