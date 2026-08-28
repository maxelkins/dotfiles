#!/usr/bin/env bash

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

install_packages() {
  local bundle="${DOT_ROOT}/packages/bundle"

  command_exists brew || fail "Homebrew is required"
  [[ -f "$bundle" ]] || fail "package bundle not found: $bundle"

  info "Installing packages"
  brew bundle --file="$bundle"
}

check_packages() {
  local bundle="${DOT_ROOT}/packages/bundle"

  command_exists brew || fail "Homebrew is required"
  [[ -f "$bundle" ]] || fail "package bundle not found: $bundle"

  brew bundle check --no-upgrade --file="$bundle"
}

update_packages() {
  command_exists brew || fail "Homebrew is required"
  info "Updating Homebrew"
  brew update
  install_packages
}
