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
  success "saved package profile: $profile"
}

choose_initial_profile() {
  local requested="${1:-}"
  local file
  file="$(profile_file)"

  if [[ -n "$requested" ]]; then
    validate_profile "$requested"
    printf '%s\n' "$requested"
    return 0
  fi

  if [[ -f "$file" ]]; then
    current_profile
    return 0
  fi

  if [[ ! -t 0 ]]; then
    printf 'base\n'
    return 0
  fi

  local choice
  printf 'Package profile [base/personal/work] (base): ' >&2
  IFS= read -r choice
  choice="${choice:-base}"
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
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew_environment
  command_exists brew || fail "Homebrew installed but is unavailable in PATH"
}

trust_declared_formulae() {
  local trust_file="${DOT_ROOT}/packages/trusted-formulae"
  local formula

  [[ -f "$trust_file" ]] || return 0

  while IFS= read -r formula; do
    [[ -n "$formula" && "$formula" != \#* ]] || continue
    info "Trusting formula $formula"
    brew trust --formula "$formula"
  done < "$trust_file"
}

install_packages() {
  local profile bundle failed=0
  profile="$(current_profile)"
  local bundles=("${DOT_ROOT}/packages/bundle")
  if [[ "$profile" != "base" ]]; then
    bundles+=("${DOT_ROOT}/packages/bundle.${profile}")
  fi

  command_exists brew || fail "Homebrew is required"
  trust_declared_formulae
  info "Installing $profile package profile"

  for bundle in "${bundles[@]}"; do
    [[ -f "$bundle" ]] || fail "package bundle not found: $bundle"
    info "Installing $(basename "$bundle")"
    if ! brew bundle --file="$bundle"; then
      warn "$(basename "$bundle") had package failures"
      failed=1
    fi
  done

  return "$failed"
}

check_packages() {
  local profile bundle failed=0
  profile="$(current_profile)"
  local bundles=("${DOT_ROOT}/packages/bundle")
  if [[ "$profile" != "base" ]]; then
    bundles+=("${DOT_ROOT}/packages/bundle.${profile}")
  fi

  command_exists brew || fail "Homebrew is required"

  for bundle in "${bundles[@]}"; do
    [[ -f "$bundle" ]] || fail "package bundle not found: $bundle"
    info "Checking $(basename "$bundle")"
    if ! brew bundle check --no-upgrade --file="$bundle"; then
      failed=1
    fi
  done

  return "$failed"
}

update_packages() {
  command_exists brew || fail "Homebrew is required"
  info "Updating Homebrew"
  brew update
  install_packages
}
