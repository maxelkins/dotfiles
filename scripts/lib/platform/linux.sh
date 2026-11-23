#!/usr/bin/env bash

# Linux (apt) platform backend for agent boxes. Sourced by scripts/lib/platform.sh.
# Requires scripts/lib/common.sh and DOT_ROOT. Functions return, never exit.

DOT_LINUX_HOOK_BEGIN='# >>> dot PATH hook >>>'
DOT_LINUX_HOOK_END='# <<< dot PATH hook <<<'
# shellcheck disable=SC2016 # expanded by the shell that sources the hook
DOT_LINUX_ENV_FILE='$HOME/.config/dotfiles/env.sh'

platform_label() {
  printf 'this Linux box\n'
}

# Linux boxes install a single bundle; there are no package profiles.
platform_supports_profiles() {
  return 1
}

platform_required_tools() {
  printf '%s\n' stow git asdf
}

# Top-level home/ entries that are not linked on Linux.
platform_home_excludes() {
  printf '%s\n' Library
}

linux_bundle_file() {
  printf '%s/packages/bundle.linux\n' "$DOT_ROOT"
}

linux_asdf_pin_file() {
  printf '%s/packages/asdf.linux\n' "$DOT_ROOT"
}

linux_is_root() {
  [[ "$(id -u)" == 0 ]]
}

linux_as_root() {
  if linux_is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

linux_apt_get() {
  linux_as_root env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@"
}

platform_prepare() {
  info "Checking Linux prerequisites"
  if ! command_exists apt-get || ! command_exists dpkg-query; then
    error "apt-get and dpkg-query are required; dot supports Debian and Ubuntu on Linux"
    return 1
  fi
  if linux_is_root; then
    success "Running as root"
    return 0
  fi
  if ! command_exists sudo; then
    error "sudo is required to install packages; install it as root: apt-get install -y sudo"
    return 1
  fi
  if ! sudo -v; then
    error "sudo could not authenticate; dot needs sudo to run apt-get"
    return 1
  fi
  success "apt-get and sudo are available"
}

# Print bundle package names, one per line.
linux_bundle_packages() {
  local bundle
  bundle="$(linux_bundle_file)"
  if [[ ! -f "$bundle" ]]; then
    error "Package bundle is missing: $bundle"
    return 1
  fi
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$bundle"
}

linux_package_installed() {
  local status
  status="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" || return 1
  [[ "$status" == 'install ok installed' ]]
}

# Fill the named array with bundle packages that are not installed.
linux_collect_missing() {
  local -n linux_missing_ref="$1"
  local packages pkg
  linux_missing_ref=()
  packages="$(linux_bundle_packages)" || return 1
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    linux_package_installed "$pkg" || linux_missing_ref+=("$pkg")
  done <<<"$packages"
}

linux_install_missing() {
  local missing=()
  linux_collect_missing missing || return 1

  if (( ${#missing[@]} == 0 )); then
    success "All bundle packages are installed"
    return 0
  fi

  if [[ "${1:-}" != --skip-update ]]; then
    run_prefixed apt linux_apt_get update || { error "apt-get update failed"; return 1; }
  fi
  info "Installing ${#missing[@]} package(s): ${missing[*]}"
  if ! run_prefixed apt linux_apt_get install -y --no-install-recommends "${missing[@]}"; then
    error "apt-get install failed"
    return 1
  fi
  success "Bundle packages are installed"
}

platform_install_packages() {
  info "Installing Linux packages from packages/bundle.linux"
  linux_install_missing
}

platform_update_packages() {
  local packages=() pkg list

  info "Updating Linux packages from packages/bundle.linux"
  run_prefixed apt linux_apt_get update || { error "apt-get update failed"; return 1; }
  linux_install_missing --skip-update || return 1

  list="$(linux_bundle_packages)" || return 1
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && packages+=("$pkg")
  done <<<"$list"
  (( ${#packages[@]} > 0 )) || return 0

  if ! run_prefixed apt linux_apt_get install -y --only-upgrade --no-install-recommends "${packages[@]}"; then
    error "apt-get upgrade of bundle packages failed"
    return 1
  fi
  success "Bundle packages are up to date"
}

# Read-only: non-zero, listing each missing package, if any is not installed.
platform_check_packages() {
  local missing=() pkg
  if ! command_exists dpkg-query; then
    error "dpkg-query is missing; cannot check apt packages"
    return 1
  fi
  linux_collect_missing missing || return 1
  if (( ${#missing[@]} == 0 )); then
    return 0
  fi
  for pkg in "${missing[@]}"; do
    warn "apt package $pkg is not installed"
  done
  return 1
}

# Print a field from packages/asdf.linux: `version`, or `sha256 <arch>`.
linux_asdf_pin() {
  local pin value
  pin="$(linux_asdf_pin_file)"
  if [[ ! -f "$pin" ]]; then
    error "asdf pin is missing: $pin"
    return 1
  fi
  if [[ "$1" == version ]]; then
    value="$(awk '$1 == "version" { print $2; exit }' "$pin")"
    if [[ ! "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      error "No valid 'version X.Y.Z' line in $pin"
      return 1
    fi
  else
    value="$(awk -v arch="$2" '$1 == "sha256" && $2 == arch { print $3; exit }' "$pin")"
    if [[ ! "$value" =~ ^[0-9a-f]{64}$ ]]; then
      error "No valid 'sha256 $2 <hex>' line in $pin"
      return 1
    fi
  fi
  printf '%s\n' "$value"
}

linux_asdf_arch() {
  case "$(uname -m)" in
    x86_64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *)
      error "Unsupported architecture for asdf: $(uname -m)"
      return 1
      ;;
  esac
}

# `asdf version` prints e.g. "v0.20.2 (revision cb72590)"; compare the first word exactly.
linux_asdf_has_version() {
  local bin="$1" version="$2" output
  [[ -x "$bin" ]] || return 1
  output="$("$bin" version 2>/dev/null)" || return 1
  [[ "${output%% *}" == "v${version}" ]]
}

# Download, verify, and install the asdf binary. Runs in a subshell so the
# EXIT trap always removes the temporary directory.
linux_fetch_asdf() (
  local version="$1" arch="$2" expected="$3" dest="$4"
  local asset="asdf-v${version}-linux-${arch}.tar.gz"
  local url="https://github.com/asdf-vm/asdf/releases/download/v${version}/${asset}"
  local tmp actual

  tmp="$(mktemp -d)" || exit 1
  # shellcheck disable=SC2064 # expand now; tmp is local to this subshell
  trap "rm -rf '$tmp'" EXIT

  if ! curl -fsSL --retry 3 -o "${tmp}/${asset}" "$url"; then
    error "Could not download $url"
    exit 1
  fi
  actual="$(sha256sum "${tmp}/${asset}")" || exit 1
  actual="${actual%% *}"
  if [[ "$actual" != "$expected" ]]; then
    error "asdf checksum mismatch for ${asset}: expected ${expected}, got ${actual}"
    exit 1
  fi
  mkdir "${tmp}/extract" || exit 1
  if ! tar -xzf "${tmp}/${asset}" -C "${tmp}/extract"; then
    error "Could not extract ${asset}"
    exit 1
  fi
  if [[ ! -f "${tmp}/extract/asdf" ]]; then
    error "asdf binary not found in ${asset}"
    exit 1
  fi
  mkdir -p "$(dirname "$dest")" || exit 1
  install -m 0755 "${tmp}/extract/asdf" "$dest" || exit 1
)

linux_path_prepend() {
  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
  export PATH
}

linux_hook_block() {
  printf '%s\n' \
    "$DOT_LINUX_HOOK_BEGIN" \
    '# Managed by dot setup: puts ~/.local/bin and asdf shims on PATH, also for' \
    '# non-interactive shells, so it must stay above any early return.' \
    "if [ -f \"${DOT_LINUX_ENV_FILE}\" ]; then . \"${DOT_LINUX_ENV_FILE}\"; fi" \
    "$DOT_LINUX_HOOK_END"
}

# Print the file without any dot PATH hook block. An unterminated block is
# kept verbatim rather than dropping the rest of the file.
linux_strip_hook() {
  [[ -f "$1" ]] || return 0
  awk -v begin="$DOT_LINUX_HOOK_BEGIN" -v end="$DOT_LINUX_HOOK_END" '
    !skipping && $0 == begin { skipping = 1; held = $0; next }
    skipping && $0 == end { skipping = 0; held = ""; next }
    skipping { held = held "\n" $0; next }
    { print }
    END { if (skipping) print held }
  ' "$1"
}

linux_hook_current() {
  local file="$1" block
  [[ -f "$file" ]] || return 1
  block="$(linux_hook_block)"
  [[ "$(head -n "$(wc -l <<<"$block")" "$file")" == "$block" ]]
}

# Put the hook block at the top of a startup file, replacing any old copy.
linux_install_hook() {
  local file="$1" rest
  if linux_hook_current "$file"; then
    return 0
  fi
  rest="$(linux_strip_hook "$file")" || return 1
  {
    linux_hook_block
    [[ -z "$rest" ]] || printf '%s\n' "$rest"
  } >"${file}.dot-tmp" || return 1
  # Copy contents back so the file keeps its inode, mode, and any symlink.
  cat "${file}.dot-tmp" >"$file" && rm -f "${file}.dot-tmp"
}

platform_install_runtime_manager() {
  local version arch sha256 file
  local bin="${HOME}/.local/bin/asdf"

  info "Installing the asdf runtime manager"
  version="$(linux_asdf_pin version)" || return 1
  arch="$(linux_asdf_arch)" || return 1
  sha256="$(linux_asdf_pin sha256 "$arch")" || return 1

  if linux_asdf_has_version "$bin" "$version"; then
    success "asdf v${version} is already installed"
  else
    if ! command_exists curl || ! command_exists sha256sum; then
      error "curl and sha256sum are required to install asdf; run: dot setup"
      return 1
    fi
    linux_fetch_asdf "$version" "$arch" "$sha256" "$bin" || return 1
    if ! linux_asdf_has_version "$bin" "$version"; then
      error "Installed asdf does not report v${version}"
      return 1
    fi
    success "Installed asdf v${version} at ${bin}"
  fi

  linux_path_prepend "${ASDF_DATA_DIR:-${HOME}/.asdf}/shims"
  linux_path_prepend "${HOME}/.local/bin"

  for file in "${HOME}/.bashrc" "${HOME}/.profile"; do
    if ! linux_install_hook "$file"; then
      error "Could not install the shell PATH hook in $file"
      return 1
    fi
  done
  success "Shell PATH hook is installed in ~/.bashrc and ~/.profile"
}

platform_install_shell() {
  skipped "Oh My Zsh is not installed on Linux; bash uses the dot PATH hook"
}

# Doctor contract (scripts/lib/platform.sh): warn and return 1 when unhealthy;
# doctor adds the "dot setup" action itself.
platform_check_shell() {
  local file hook_missing=0
  for file in "${HOME}/.bashrc" "${HOME}/.profile"; do
    if ! linux_hook_current "$file"; then
      warn "The dot PATH hook is missing or outdated at the top of ~/${file##*/}"
      hook_missing=1
    fi
  done
  (( hook_missing == 0 )) || return 1
  success "Shell PATH hook is installed"
}
