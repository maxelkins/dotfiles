#!/usr/bin/env bash

run_doctor() {
  local mode="${1:-standalone}"
  local failures=0
  local checked=0
  local healthy_links=0
  local tool source relative target package_output
  local actions=()

  info "Checking required tools"
  for tool in brew stow git zsh; do
    if command_exists "$tool"; then
      success "$tool is available"
    else
      warn "$tool is missing"
      ((failures += 1))
      actions+=("Install missing tools: dot setup")
    fi
  done

  info "Checking managed home files"
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
    else
      ((healthy_links += 1))
    fi
  done < <(find "$DOT_HOME_DIR" -type f ! -name '.DS_Store' | LC_ALL=C sort)

  if (( checked == 0 )); then
    warn "No managed files were found"
    ((failures += 1))
    actions+=("Restore the home/ tree from Git, then run: dot apply home")
  elif (( healthy_links == checked )); then
    success "$checked managed links are correct"
  else
    warn "$((checked - healthy_links)) of $checked managed links need attention"
    actions+=("Repair managed links: dot apply home")
  fi

  if command_exists brew; then
    info "Checking the $(current_profile) package profile"
    if package_output="$(check_packages 2>&1)"; then
      success "Declared packages are installed"
    else
      printf '%s\n' "$package_output" >&2
      warn "One or more declared packages are missing or outdated"
      ((failures += 1))
      actions+=("Reconcile packages: dot upgrade")
    fi
  fi

  info "Checking the Pi runtime"
  if check_pi_install; then
    success "Pi $(pi_version) uses Node $(pi_node_version)"
  else
    warn "Pi installation is missing or broken"
    ((failures += 1))
    actions+=("Reinstall or update Pi: dot upgrade")
  fi

  info "Checking the shell framework"
  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    warn "Oh My Zsh is missing"
    ((failures += 1))
    actions+=("Install shell dependencies: dot setup")
  else
    success "Oh My Zsh is installed"
  fi

  if (( failures > 0 )); then
    if [[ "$mode" == "standalone" ]]; then
      print_summary "$failures health check(s) failed; the setup needs attention"
      print_action_required "${actions[@]}"
    else
      warn "$failures health check(s) failed"
    fi
    return 1
  fi

  if [[ "$mode" == "standalone" ]]; then
    print_summary "All checks passed; no action is required"
  else
    success "All health checks passed"
  fi
}
