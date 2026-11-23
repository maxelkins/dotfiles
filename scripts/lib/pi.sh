#!/usr/bin/env bash

PI_NPM_PACKAGE="@earendil-works/pi-coding-agent"
PI_RUNTIME_DIR="${DOT_HOME_DIR}/.config/pi-runtime"
readonly PI_NPM_PACKAGE PI_RUNTIME_DIR

pi_node_version() {
  (
    cd "$PI_RUNTIME_DIR" || exit
    asdf current nodejs | awk '$1 == "nodejs" { print $2; exit }'
  )
}

pi_node_dir() {
  (
    cd "$PI_RUNTIME_DIR" || exit
    asdf where nodejs
  )
}

pi_version() {
  local node_dir
  node_dir="$(pi_node_dir)" || return 1
  "$node_dir/bin/node" "$node_dir/bin/pi" --version
}

install_pi() {
  if ! command_exists asdf; then
    error "asdf is required to install Pi; run: dot setup"
    return 1
  fi
  if [[ ! -f "${PI_RUNTIME_DIR}/.tool-versions" ]]; then
    error "Pi .tool-versions is missing; restore it from the repository"
    return 1
  fi

  local node_dir node_version npm_cli
  if ! asdf plugin list | grep -qx nodejs; then
    info "Adding the asdf Node.js plugin"
    run_prefixed asdf asdf plugin add nodejs || return 1
  fi

  info "Installing Pi with its isolated asdf runtime"
  run_prefixed asdf bash -c 'cd "$1" && asdf install nodejs' _ "$PI_RUNTIME_DIR" || return 1

  node_dir="$(pi_node_dir)" || return 1
  node_version="$(pi_node_version)" || return 1
  npm_cli="${node_dir}/lib/node_modules/npm/bin/npm-cli.js"
  if [[ ! -x "${node_dir}/bin/node" || ! -f "$npm_cli" ]]; then
    error "Pi's Node installation is incomplete"
    return 1
  fi

  run_prefixed npm "$node_dir/bin/node" "$npm_cli" install -g --ignore-scripts --min-release-age=0 --no-fund --no-audit "$PI_NPM_PACKAGE" || return 1
  run_prefixed asdf asdf reshim nodejs "$node_version" || return 1

  if ! check_pi_install; then
    error "Pi installation check failed"
    return 1
  fi
  success "Pi $(pi_version) uses Node $node_version"
}

check_pi_install() {
  command_exists asdf || return 1
  [[ -f "${PI_RUNTIME_DIR}/.tool-versions" ]] || return 1

  local node_dir
  node_dir="$(pi_node_dir)" || return 1
  [[ -x "${node_dir}/bin/node" && -f "${node_dir}/bin/pi" ]] || return 1
  "$node_dir/bin/node" -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)' || return 1
  "$node_dir/bin/node" "$node_dir/bin/pi" --version >/dev/null
}

# Shared Pi settings live in templates/pi/settings.json and merge into the
# local ~/.pi/agent/settings.json, which Pi rewrites at runtime. The merge runs
# on Pi's own Node, so it needs no extra tools. See scripts/lib/pi-settings.mjs.
pi_settings_node() {
  local node_dir
  node_dir="$(pi_node_dir 2>/dev/null)" || return 1
  [[ -x "${node_dir}/bin/node" ]] || return 1
  printf '%s/bin/node\n' "$node_dir"
}

pi_settings() {
  local node
  node="$(pi_settings_node)" || return 3
  "$node" "${DOT_ROOT}/scripts/lib/pi-settings.mjs" "$1" \
    "${DOT_ROOT}/templates/pi/settings.json" "${HOME}/.pi/agent/settings.json"
}

apply_pi_settings() {
  local status=0
  info "Applying shared Pi settings"
  pi_settings apply || status=$?
  case "$status" in
    0) success "~/.pi/agent/settings.json has the shared Pi settings" ;;
    3)
      error "Pi's Node is missing, so shared Pi settings were not applied; run: dot setup"
      return 1
      ;;
    *)
      error "Shared Pi settings could not be applied"
      return 1
      ;;
  esac
}

check_pi_settings() {
  local output status=0 line
  output="$(pi_settings check 2>&1)" || status=$?
  if (( status == 3 )); then
    warn "Pi's Node is missing, so Pi settings were not checked"
    return 1
  fi
  if (( status == 0 )); then
    success "~/.pi/agent/settings.json has the shared Pi settings"
    return 0
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && warn "$line"
  done <<<"$output"
  return 1
}
