#!/usr/bin/env bash

# Reusable Linux agent-box implementation. Sourced by scripts/linux-agent.sh.
# Uses output helpers from scripts/lib/common.sh.

# asdf's own version is pinned in the repo-root .tool-versions alongside the
# runtimes it manages; every version statement lives in that one file.
readonly DOT_LINUX_ASDF_BIN="${HOME}/.local/bin/asdf"

bundle_packages() {
  # Print non-comment lines of a bundle file.
  grep -vE '^[[:space:]]*(#|$)' "$1"
}

apt_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

apt_install_bundle() {
  local bundle="$1"
  local missing=()
  local pkg

  while IFS= read -r pkg; do
    apt_package_installed "$pkg" || missing+=("$pkg")
  done < <(bundle_packages "$bundle")

  if (( ${#missing[@]} == 0 )); then
    success "All bundle packages are already installed"
    return 0
  fi

  info "Installing ${#missing[@]} package(s): ${missing[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends "${missing[@]}"
  success "Bundle packages are installed"
}

apt_drift_report() {
  # Read-only report. Fresh boxes drift the most: apt-mark showmanual lists
  # everything the base image installed by hand.
  local bundle="$1"
  local diff_status=0

  info "Reporting apt drift (read-only)"
  diff <(apt-mark showmanual | LC_ALL=C sort) \
    <(bundle_packages "$bundle" | LC_ALL=C sort) || diff_status=$?

  if (( diff_status == 0 )); then
    success "apt manual set matches the bundle"
  else
    warn "apt drift shown above: '<' = installed but unlisted, '>' = listed but not yet manual"
  fi
}

asdf_pinned_version() {
  # The asdf version pinned in a .tool-versions file, with the v prefix used
  # by release assets.
  local pinned
  pinned="$(awk '$1 == "asdf" {print $2; exit}' "$1")"
  if [[ -z "$pinned" ]]; then
    error "no asdf version found in $1; add an 'asdf <version>' line"
    return 1
  fi
  printf '%s\n' "v${pinned#v}"
}

install_asdf() {
  local tool_versions="$1"
  local version arch="" bin="$DOT_LINUX_ASDF_BIN"
  local asset url tmp extracted_bin

  version="$(asdf_pinned_version "$tool_versions")"

  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) fail "unsupported architecture for asdf: $(uname -m)" ;;
  esac

  if [[ -x "$bin" ]] && "$bin" version 2>/dev/null | grep -qF "${version#v}"; then
    success "asdf ${version} is already installed"
    return 0
  fi

  asset="asdf-${version}-linux-${arch}.tar.gz"
  url="https://github.com/asdf-vm/asdf/releases/download/${version}/${asset}"
  tmp="$(mktemp -d)"

  info "Downloading asdf ${version}"
  mkdir -p "$(dirname "$bin")"
  curl -fsSLo "$tmp/$asset" "$url"
  curl -fsSLo "$tmp/$asset.md5" "${url}.md5"
  (cd "$tmp" && md5sum -c "$asset.md5")

  tar -xzf "$tmp/$asset" -C "$tmp"
  extracted_bin="$(find "$tmp" -maxdepth 2 -type f -name asdf | head -n 1)"
  if [[ -z "$extracted_bin" ]]; then
    error "asdf binary not found in ${asset}"
    rm -rf "$tmp"
    return 1
  fi

  install -m 0755 "$extracted_bin" "$bin"
  rm -rf "$tmp"
  success "Installed asdf ${version} at $bin"
}

asdf_ensure_plugins() {
  # Ensure every tool named in a .tool-versions file has its plugin added.
  # Uses asdf's official short-name registry, the same path as manual use;
  # .tool-versions remains the single source of truth for both plugins
  # (tool names) and versions. The asdf entry is skipped: the manager
  # installs itself via install_asdf, never through the plugin.
  local tool_versions="$1"
  local name

  [[ -x "$DOT_LINUX_ASDF_BIN" ]] || fail "asdf is required; run install_asdf first"

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if "$DOT_LINUX_ASDF_BIN" plugin list | grep -qxF "$name"; then
      success "asdf plugin ${name} is already added"
    else
      info "Adding asdf plugin ${name}"
      "$DOT_LINUX_ASDF_BIN" plugin add "$name"
    fi
  done < <(awk '!/^[[:space:]]*(#|$)/ && $1 != "asdf" {print $1}' "$tool_versions")
}

asdf_install_tool_versions() {
  # Installs every runtime pinned in a .tool-versions file. Blanket
  # `asdf install` skips already-installed versions. The asdf line is
  # filtered out: the manager never installs itself through the plugin.
  local tool_versions="$1"
  local workdir

  [[ -x "$DOT_LINUX_ASDF_BIN" ]] || fail "asdf is required; run install_asdf first"

  workdir="$(mktemp -d)"
  grep -vE '^[[:space:]]*(#|$)' "$tool_versions" |
    awk '$1 != "asdf' >"${workdir}/.tool-versions"

  info "Installing runtimes from ${tool_versions} (asdf line excluded)"
  (cd "$workdir" && "$DOT_LINUX_ASDF_BIN" install)
  rm -rf "$workdir"
  success "asdf runtimes match .tool-versions"
}
