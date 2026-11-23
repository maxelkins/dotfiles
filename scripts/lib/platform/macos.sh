#!/usr/bin/env bash
#
# macOS backend for the platform layer in scripts/lib/platform.sh.

# shellcheck source=scripts/lib/brew.sh
source "${DOT_ROOT}/scripts/lib/brew.sh"

platform_label() {
  printf 'this Mac\n'
}

platform_supports_profiles() {
  return 0
}

platform_required_tools() {
  printf '%s\n' brew stow git zsh
}

platform_home_excludes() {
  :
}

platform_prepare() {
  if ! install_homebrew; then
    skipped "Package installation requires Homebrew"
    return 1
  fi
}

platform_install_packages() {
  install_packages
}

platform_update_packages() {
  update_packages
}

# Brew missing is already reported by the required tools check.
platform_packages_checkable() {
  command_exists brew
}

platform_check_packages() {
  check_packages
}

# asdf comes from the Homebrew bundle.
platform_install_runtime_manager() {
  return 0
}

platform_install_shell() {
  info "Installing shell dependencies"
  if run_prefixed Shell bash "${DOT_ROOT}/scripts/ohmyzsh.sh"; then
    success "Shell dependencies are installed"
  else
    error "Shell dependency installation failed"
    return 1
  fi
}

platform_check_shell() {
  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    warn "Oh My Zsh is missing"
    return 1
  fi
  success "Oh My Zsh is installed"
}
