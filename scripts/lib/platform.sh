#!/usr/bin/env bash
#
# Platform layer. `dot` sources this file after common.sh. It detects the host
# platform and sources scripts/lib/platform/<name>.sh when that backend exists.
# Without a backend nothing below is defined except the defaults in this file,
# and require_supported_platform fails.
#
# Every backend must define:
#
#   platform_label                   Print a short human label, e.g. "this Mac".
#   platform_supports_profiles       Return 0 when the base/personal/work package
#                                    profiles apply on this platform.
#   platform_required_tools          Print the tools `dot check` requires, one per
#                                    line.
#   platform_prepare                 Install one-time prerequisites before
#                                    packages. On failure, report the error and
#                                    what is skipped as a result, then return
#                                    non-zero; setup then skips package
#                                    installation.
#   platform_install_packages        Install and reconcile declared packages.
#   platform_update_packages         Refresh package metadata, then reconcile.
#   platform_check_packages          Read-only package check. Doctor captures
#                                    stdout and stderr together and prints them
#                                    only on failure. Return 0 when every
#                                    declared package is installed, else 1.
#   platform_install_runtime_manager Ensure `asdf` is on PATH for install_pi.
#   platform_install_shell           Install shell dependencies with the usual
#                                    info/success/error messages. Return
#                                    non-zero on failure.
#   platform_check_shell             Read-only shell framework check, run by
#                                    doctor in the current shell after it prints
#                                    "Checking shell". Print one
#                                    success line (via success) when healthy and
#                                    return 0. When unhealthy, print a warning
#                                    (via warn) naming what is missing and return
#                                    1; doctor then counts one failure and adds
#                                    the shell row's action from
#                                    scripts/lib/steps.sh. Do not print the
#                                    action yourself.
#
# A backend may override these defaults:
#
#   platform_home_excludes           Print top-level names under home/ that must
#                                    not be linked or checked on this platform,
#                                    one per line (e.g. "Library"). Default:
#                                    nothing.
#   platform_packages_checkable      Return 0 when doctor should run
#                                    platform_check_packages. Return non-zero to
#                                    skip the package check silently, e.g. when
#                                    the package manager is missing and the tool
#                                    check already reports it. Default: 0.
#   platform_skips_step <name>       Return 0 when a row of scripts/lib/steps.sh
#                                    does not apply on this platform; setup,
#                                    upgrade, and doctor then ignore it.
#                                    Default: 1 (every step applies).

DOT_PLATFORM_BACKEND_LOADED=0

dot_platform() {
  if [[ -n "${DOT_PLATFORM:-}" ]]; then
    printf '%s\n' "$DOT_PLATFORM"
    return 0
  fi

  case "$(uname -s)" in
    Darwin) printf 'macos\n' ;;
    Linux) printf 'linux\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

platform_home_excludes() {
  :
}

platform_packages_checkable() {
  return 0
}

platform_skips_step() {
  return 1
}

require_supported_platform() {
  if (( DOT_PLATFORM_BACKEND_LOADED == 1 )); then
    return 0
  fi

  local name
  name="$(dot_platform)"
  if [[ "$name" == unsupported ]]; then
    fail "unsupported platform: $(uname -s)"
  else
    fail "unsupported platform: $name (no backend at scripts/lib/platform/${name}.sh)"
  fi
}

load_platform_backend() {
  local name backend
  name="$(dot_platform)"
  [[ "$name" =~ ^[a-z0-9_-]+$ && "$name" != unsupported ]] || return 0

  backend="${DOT_ROOT}/scripts/lib/platform/${name}.sh"
  [[ -f "$backend" ]] || return 0

  # shellcheck source=/dev/null
  source "$backend"
  DOT_PLATFORM_BACKEND_LOADED=1
}

load_platform_backend
