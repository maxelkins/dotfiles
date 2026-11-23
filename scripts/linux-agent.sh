#!/usr/bin/env bash
set -euo pipefail

# Explicit Linux agent-box mutations. Opt-in, like scripts/macos.sh.
# Intended dispatch (not yet wired into `dot`):
#   run_prefixed Linux bash "${DOT_ROOT}/scripts/linux-agent.sh"
#
# Requires sudo for apt only; asdf and runtimes are user-level.
# Verification: bash -n scripts/linux-agent.sh scripts/lib/linux.sh

DOT_ROOT="${DOT_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DOT_ROOT

# shellcheck source=scripts/lib/common.sh
source "${DOT_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/linux.sh
source "${DOT_ROOT}/scripts/lib/linux.sh"

export PATH="${HOME}/.local/bin:${HOME}/.asdf/shims:${PATH}"

main() {
  info "Setting up this Linux agent box: packages, asdf, plugins, runtimes"

  require_linux

  info "Installing apt packages from packages/bundle.linux-agent"
  apt_install_bundle "${DOT_ROOT}/packages/bundle.linux-agent"

  install_asdf "${DOT_ROOT}/.tool-versions"

  info "Ensuring asdf plugins from .tool-versions"
  asdf_ensure_plugins "${DOT_ROOT}/.tool-versions"

  asdf_install_tool_versions "$DOT_ROOT"

  apt_drift_report "${DOT_ROOT}/packages/bundle.linux-agent"

  print_summary "Agent-box setup completed successfully"
  print_next_action "Run: dot apply home  (then add ~/.asdf/shims to PATH in your shell rc if missing)"
}

main "$@"
