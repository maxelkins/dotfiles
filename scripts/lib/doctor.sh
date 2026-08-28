#!/usr/bin/env bash

run_doctor() {
  local failures=0
  local checked=0
  local tool source relative target

  info "Checking required tools"
  for tool in brew stow git zsh; do
    if command_exists "$tool"; then
      success "$tool"
    else
      warn "$tool is missing"
      ((failures += 1))
    fi
  done

  info "Checking managed files"
  while IFS= read -r source; do
    ((checked += 1))
    relative="${source#${DOT_HOME_DIR}/}"
    target="${HOME}/${relative}"

    if [[ ! -L "$target" ]]; then
      warn "~/${relative} is not a symlink"
      ((failures += 1))
    elif [[ ! -e "$target" ]]; then
      warn "~/${relative} is a broken symlink"
      ((failures += 1))
    elif [[ ! "$target" -ef "$source" ]]; then
      warn "~/${relative} points outside this repository"
      ((failures += 1))
    fi
  done < <(find "$DOT_HOME_DIR" -type f | LC_ALL=C sort)

  if (( checked == 0 )); then
    warn "no managed files found"
    ((failures += 1))
  else
    success "$checked managed files checked"
  fi

  if command_exists brew; then
    info "Checking package bundle"
    if check_packages >/dev/null 2>&1; then
      success "declared packages are installed"
    else
      warn "one or more declared packages are missing"
      ((failures += 1))
    fi
  fi

  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    warn "Oh My Zsh is missing"
    ((failures += 1))
  else
    success "Oh My Zsh"
  fi

  if (( failures > 0 )); then
    fail "$failures check(s) failed"
    return 1
  fi

  success "setup is healthy"
}
