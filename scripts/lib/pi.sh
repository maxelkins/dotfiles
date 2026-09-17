#!/usr/bin/env bash

PI_NPM_PACKAGE="@earendil-works/pi-coding-agent"
PI_RUNTIME_DIR="${DOT_HOME_DIR}/.config/pi-runtime"
readonly PI_NPM_PACKAGE PI_RUNTIME_DIR

pi_node_version() {
  (
    cd "$PI_RUNTIME_DIR"
    asdf current nodejs | awk '$1 == "nodejs" { print $2; exit }'
  )
}

pi_node_dir() {
  (
    cd "$PI_RUNTIME_DIR"
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
    fail "asdf is required to install Pi"
    return 1
  fi
  if [[ ! -f "${PI_RUNTIME_DIR}/.tool-versions" ]]; then
    fail "Pi .tool-versions is missing"
    return 1
  fi

  local node_dir node_version npm_cli
  if ! asdf plugin list | grep -qx nodejs; then
    info "Adding the asdf nodejs plugin"
    asdf plugin add nodejs || return 1
  fi

  info "Installing Pi with its asdf runtime"
  (
    cd "$PI_RUNTIME_DIR"
    asdf install nodejs
  ) || return 1

  node_dir="$(pi_node_dir)" || return 1
  node_version="$(pi_node_version)" || return 1
  npm_cli="${node_dir}/lib/node_modules/npm/bin/npm-cli.js"
  if [[ ! -x "${node_dir}/bin/node" || ! -f "$npm_cli" ]]; then
    fail "Pi's Node installation is incomplete"
    return 1
  fi

  "$node_dir/bin/node" "$npm_cli" install -g --ignore-scripts --min-release-age=0 --no-fund --no-audit "$PI_NPM_PACKAGE" || return 1
  asdf reshim nodejs "$node_version" || return 1

  if ! check_pi_install; then
    fail "Pi installation check failed"
    return 1
  fi
  success "Pi $(pi_version) using Node $node_version"
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
