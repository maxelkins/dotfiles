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

linux_apt_sources_file() {
  printf '%s/packages/apt-sources.linux\n' "$DOT_ROOT"
}

linux_extras_file() {
  printf '%s/packages/extras.linux\n' "$DOT_ROOT"
}

linux_is_root() {
  [[ "$(id -u)" == 0 ]]
}

# Without a user to answer, sudo must fail rather than ask for a password.
linux_as_root() {
  if linux_is_root; then
    "$@"
  elif dot_interactive; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

linux_apt_get() {
  local dpkg_options=()
  # Headless: keep locally modified config files instead of asking.
  if dot_headless; then
    dpkg_options=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
  fi
  linux_as_root env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    apt-get ${dpkg_options[@]+"${dpkg_options[@]}"} "$@"
}

# Check sudo up front. Interactive runs may ask for the password once;
# otherwise fail fast instead of hanging on a prompt nobody can answer.
linux_check_sudo() {
  if dot_interactive; then
    if ! sudo -v; then
      error "sudo could not authenticate; dot needs sudo to run apt-get"
      return 1
    fi
    return 0
  fi
  if sudo -n true 2>/dev/null; then
    return 0
  fi
  if dot_headless; then
    error "sudo needs a password; configure passwordless sudo for unattended runs or run without --headless"
  else
    error "sudo needs a password; configure passwordless sudo for unattended runs or run dot from a terminal"
  fi
  return 1
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
  if ! linux_check_sudo; then
    skipped "apt package installation requires sudo"
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
  linux_install_apt_sources || return 1
  info "Installing Linux packages from packages/bundle.linux"
  linux_install_missing
}

platform_update_packages() {
  local packages=() pkg list

  linux_install_apt_sources || return 1
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

# Read-only: non-zero, listing each missing or stale apt repository, each
# missing apt package, and each missing or outdated release binary from
# packages/extras.linux.
platform_check_packages() {
  local missing=() pkg failed=0
  linux_check_apt_sources || failed=1
  if ! command_exists dpkg-query; then
    error "dpkg-query is missing; cannot check apt packages"
    failed=1
  elif linux_collect_missing missing; then
    for pkg in ${missing[@]+"${missing[@]}"}; do
      warn "apt package $pkg is not installed"
      failed=1
    done
  else
    failed=1
  fi
  linux_check_extras || failed=1
  return "$failed"
}

# Block tables: packages/apt-sources.linux and packages/extras.linux share an
# INI-like format of `[name]` headers followed by `key = value` lines.

# Print the block names in a table, one per line.
linux_block_names() {
  local file="$1" names name
  if [[ ! -f "$file" ]]; then
    error "Table is missing: $file"
    return 1
  fi
  names="$(awk '/^[[:space:]]*\[/ { line = $0; gsub(/[][[:space:]]/, "", line); print line }' "$file")"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      error "Invalid block name '[$name]' in $file"
      return 1
    fi
    printf '%s\n' "$name"
  done <<<"$names"
}

# Print the raw value of a key in a named block; fail when it is absent.
linux_block_value() {
  awk -v name="$2" -v key="$3" '
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*\[/ { line = $0; gsub(/[][[:space:]]/, "", line); in_block = (line == name); next }
    in_block {
      eq = index($0, "=")
      if (!eq) next
      k = substr($0, 1, eq - 1); v = substr($0, eq + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (k == key) { print v; found = 1; exit }
    }
    END { exit !found }
  ' "$1"
}

# Third-party apt repositories from packages/apt-sources.linux (format
# documented in that file). Each gets a keyring and a list file named after
# its block, so dot can tell which files it owns.

# apt reads a keyring as ASCII-armored only when it ends in .asc, so keep
# the key URL's binary .gpg extension when it has one.
linux_apt_keyring() {
  local ext=asc url
  url="$(linux_apt_source_field "$1" key)" || return 1
  [[ "$url" != *.gpg ]] || ext=gpg
  printf '/etc/apt/keyrings/%s.%s\n' "$1" "$ext"
}

linux_apt_list() {
  printf '/etc/apt/sources.list.d/%s.list\n' "$1"
}

# Print a validated field of a repository block.
linux_apt_source_field() {
  local name="$1" key="$2" file value
  file="$(linux_apt_sources_file)"
  if ! value="$(linux_block_value "$file" "$name" "$key")" || [[ -z "$value" ]]; then
    error "[$name] in $file has no '$key' value"
    return 1
  fi
  case "$key" in
    key)
      if [[ ! "$value" =~ ^https://[^[:space:]]+$ ]]; then
        error "[$name] key must be an https URL: $value"
        return 1
      fi
      ;;
    fingerprint)
      if [[ ! "$value" =~ ^[0-9A-F]{40}([[:space:]]+[0-9A-F]{40})*$ ]]; then
        error "[$name] fingerprint must be one or more 40-digit uppercase hex fingerprints: $value"
        return 1
      fi
      # One per line, sorted, to compare with linux_key_fingerprints.
      value="$(tr -s '[:space:]' '\n' <<<"$value" | sort)"
      ;;
    source)
      if [[ ! "$value" =~ ^https://[^[:space:]]+([[:space:]]+[^[:space:]]+)+$ ]]; then
        error "[$name] source must be '<https uri> <suite> [components]': $value"
        return 1
      fi
      ;;
  esac
  printf '%s\n' "$value"
}

# Print the primary-key fingerprints in a key file, sorted, one per line.
# Uses a throwaway GnuPG home so nothing touches ~/.gnupg.
linux_key_fingerprints() (
  local home
  home="$(mktemp -d)" || exit 1
  # shellcheck disable=SC2064 # expand now; home is local to this subshell
  trap "rm -rf '$home'" EXIT
  gpg --homedir "$home" --batch --show-keys --with-colons "$1" 2>/dev/null |
    awk -F: '$1 == "pub" { want = 1; next } want && $1 == "fpr" { print $10; want = 0 }' |
    sort
)

linux_apt_list_line() {
  local keyring
  keyring="$(linux_apt_keyring "$1")" || return 1
  printf 'deb [signed-by=%s] %s\n' "$keyring" "$2"
}

# True when the keyring holds exactly the pinned key and the list file matches.
linux_apt_source_current() {
  local name="$1" fingerprint source keyring list
  fingerprint="$(linux_apt_source_field "$name" fingerprint)" || return 1
  source="$(linux_apt_source_field "$name" source)" || return 1
  keyring="$(linux_apt_keyring "$name")" || return 1
  list="$(linux_apt_list "$name")"
  [[ -f "$keyring" && -f "$list" ]] || return 1
  [[ "$(linux_key_fingerprints "$keyring")" == "$fingerprint" ]] || return 1
  [[ "$(<"$list")" == "$(linux_apt_list_line "$name" "$source")" ]]
}

# A fresh box may lack curl or gpg, which adding a repository needs before
# the bundle can install them.
linux_ensure_source_tools() {
  local missing=()
  command_exists curl || missing+=(curl ca-certificates)
  command_exists gpg || missing+=(gnupg)
  (( ${#missing[@]} > 0 )) || return 0
  info "Installing ${missing[*]} to add apt repositories"
  run_prefixed apt linux_apt_get update || { error "apt-get update failed"; return 1; }
  run_prefixed apt linux_apt_get install -y --no-install-recommends "${missing[@]}" ||
    { error "apt-get install failed"; return 1; }
}

# Download the signing key, refuse it unless it is exactly the pinned key,
# then install the keyring and list file. Runs in a subshell so the EXIT trap
# always removes the temporary directory.
linux_install_apt_source() (
  local name="$1" url fingerprint source tmp actual keyring
  url="$(linux_apt_source_field "$name" key)" || exit 1
  keyring="$(linux_apt_keyring "$name")" || exit 1
  fingerprint="$(linux_apt_source_field "$name" fingerprint)" || exit 1
  source="$(linux_apt_source_field "$name" source)" || exit 1

  tmp="$(mktemp -d)" || exit 1
  # shellcheck disable=SC2064 # expand now; tmp is local to this subshell
  trap "rm -rf '$tmp'" EXIT
  chmod 0755 "$tmp" || exit 1

  if ! curl -fsSL --retry 3 -o "${tmp}/key" "$url"; then
    error "Could not download $url"
    exit 1
  fi
  actual="$(linux_key_fingerprints "${tmp}/key")"
  if [[ "$actual" != "$fingerprint" ]]; then
    error "$name signing keys do not match the pinned fingerprints ${fingerprint//$'\n'/ }; got: ${actual//$'\n'/ }"
    exit 1
  fi
  linux_apt_list_line "$name" "$source" >"${tmp}/list" || exit 1
  linux_as_root install -d -m 0755 /etc/apt/keyrings || exit 1
  linux_as_root install -m 0644 "${tmp}/key" "$keyring" || exit 1
  linux_as_root install -m 0644 "${tmp}/list" "$(linux_apt_list "$name")" || exit 1
)

# Add each missing or changed repository; keep going after a failure.
linux_install_apt_sources() {
  local names name failed=0
  names="$(linux_block_names "$(linux_apt_sources_file)")" || return 1
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    command_exists gpg && linux_apt_source_current "$name" && continue
    linux_ensure_source_tools || return 1
    if linux_install_apt_source "$name"; then
      success "Added apt repository $name"
    else
      failed=1
    fi
  done <<<"$names"
  return "$failed"
}

# Read-only: warn about each missing or stale repository and return 1 if any.
linux_check_apt_sources() {
  local names name failed=0
  names="$(linux_block_names "$(linux_apt_sources_file)")" || return 1
  [[ -n "$names" ]] || return 0
  if ! command_exists gpg; then
    warn "gpg is missing; cannot verify apt repository keys"
    return 1
  fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if ! linux_apt_source_current "$name"; then
      warn "apt repository $name is missing or does not match packages/apt-sources.linux"
      failed=1
    fi
  done <<<"$names"
  return "$failed"
}

# Release binaries from packages/extras.linux (format documented in that file).

# Versions resolved for tools whose block says `version = latest`, by name.
declare -gA LINUX_EXTRA_LATEST=()

linux_extras_bin_dir() {
  printf '%s/.local/bin\n' "$HOME"
}

# Print the tool names in packages/extras.linux, one per line.
linux_extras_names() {
  linux_block_names "$(linux_extras_file)"
}

# Print the raw value of a key in a tool's block; fail when it is absent.
linux_extra_raw() {
  linux_block_value "$(linux_extras_file)" "$1" "$2"
}

# The host architecture under the names used for sha256.<arch> keys.
linux_extras_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *)
      error "Unsupported architecture for release binaries: $(uname -m)"
      return 1
      ;;
  esac
}

# The host architecture under the tool's own naming (its optional arch map).
linux_extra_arch() {
  local name="$1" arch map pair
  local pairs=()
  arch="$(linux_extras_arch)" || return 1
  if ! map="$(linux_extra_raw "$name" arch)"; then
    printf '%s\n' "$arch"
    return 0
  fi
  read -r -a pairs <<<"$map"
  for pair in ${pairs[@]+"${pairs[@]}"}; do
    if [[ "${pair%%=*}" == "$arch" && "$pair" == *=?* ]]; then
      printf '%s\n' "${pair#*=}"
      return 0
    fi
  done
  error "[$name] arch in $(linux_extras_file) has no '${arch}=<name>' entry"
  return 1
}

# Print a validated field with {version} and {arch} expanded.
linux_extra_field() {
  local name="$1" key="$2" value version arch
  if ! value="$(linux_extra_raw "$name" "$key")" || [[ -z "$value" ]]; then
    error "[$name] in $(linux_extras_file) has no '$key' value"
    return 1
  fi
  case "$key" in
    version)
      if [[ "$value" == latest ]]; then
        value="${LINUX_EXTRA_LATEST[$name]:-}"
        if [[ -z "$value" ]]; then
          error "[$name] latest version has not been resolved"
          return 1
        fi
      fi
      if [[ ! "$value" =~ ^[0-9][0-9A-Za-z.+-]*$ ]]; then
        error "[$name] version '$value' is not a release version"
        return 1
      fi
      ;;
    sha256.*)
      if [[ ! "$value" =~ ^[0-9a-f]{64}$ ]]; then
        error "[$name] $key is not a lowercase SHA-256 hex digest"
        return 1
      fi
      ;;
  esac
  if [[ "$value" == *'{version}'* ]]; then
    version="$(linux_extra_field "$name" version)" || return 1
    value="${value//'{version}'/$version}"
  fi
  if [[ "$value" == *'{arch}'* ]]; then
    arch="$(linux_extra_arch "$name")" || return 1
    value="${value//'{arch}'/$arch}"
  fi
  case "$key" in
    url)
      if [[ ! "$value" =~ ^https://.+\.(tar\.gz|tgz)$ ]]; then
        error "[$name] url must be an https .tar.gz or .tgz asset: $value"
        return 1
      fi
      ;;
    latest | checksums)
      if [[ ! "$value" =~ ^https://[^[:space:]]+$ ]]; then
        error "[$name] $key must be an https URL: $value"
        return 1
      fi
      ;;
    binary)
      if [[ "$value" == /* || "/${value}/" == */../* ]]; then
        error "[$name] binary must be a relative path inside the archive: $value"
        return 1
      fi
      ;;
  esac
  printf '%s\n' "$value"
}

# Print the first output line of `bin check-args`; fail if it cannot run.
linux_extra_version_line() {
  local bin="$1" check="$2" output
  local args=()
  [[ -x "$bin" ]] || return 1
  read -r -a args <<<"$check"
  output="$("$bin" ${args[@]+"${args[@]}"} 2>/dev/null)" || return 1
  printf '%s\n' "${output%%$'\n'*}"
}

# True when a word of the version line equals the expected word exactly.
linux_extra_has_version() {
  local line word
  local words=()
  line="$(linux_extra_version_line "$1" "$2")" || return 1
  read -r -a words <<<"$line"
  for word in ${words[@]+"${words[@]}"}; do
    [[ "$word" == "$3" ]] && return 0
  done
  return 1
}

# Download, verify, and install one binary. Runs in a subshell so the EXIT
# trap always removes the temporary directory.
linux_fetch_extra() (
  local name="$1" url="$2" expected="$3" binary="$4" dest="$5"
  local tmp actual

  tmp="$(mktemp -d)" || exit 1
  # shellcheck disable=SC2064 # expand now; tmp is local to this subshell
  trap "rm -rf '$tmp'" EXIT

  if ! curl -fsSL --retry 3 -o "${tmp}/asset" "$url"; then
    error "Could not download $url"
    exit 1
  fi
  actual="$(sha256sum "${tmp}/asset")" || exit 1
  actual="${actual%% *}"
  if [[ "$actual" != "$expected" ]]; then
    error "$name checksum mismatch for ${url##*/}: expected ${expected}, got ${actual}"
    exit 1
  fi
  mkdir "${tmp}/extract" || exit 1
  if ! tar -xzf "${tmp}/asset" -C "${tmp}/extract"; then
    error "Could not extract ${url##*/}"
    exit 1
  fi
  if [[ ! -f "${tmp}/extract/${binary}" ]]; then
    error "$binary not found in ${url##*/}"
    exit 1
  fi
  mkdir -p "$(dirname "$dest")" || exit 1
  install -m 0755 "${tmp}/extract/${binary}" "$dest" || exit 1
)

# True when the tool's block says `version = latest`.
linux_extra_tracks_latest() {
  [[ "$(linux_extra_raw "$1" version 2>/dev/null)" == latest ]]
}

# Look up the newest release from the `latest` URL, which must redirect to a
# URL ending in the release tag (v1.2.3 or 1.2.3). Sets LINUX_EXTRA_LATEST, so
# call it in the current shell, not in $(...).
linux_resolve_extra_latest() {
  local name="$1" url location version
  url="$(linux_extra_field "$name" latest)" || return 1
  if ! location="$(curl -fsSI --retry 3 -o /dev/null -w '%{redirect_url}' "$url")" ||
    [[ -z "$location" ]]; then
    error "Could not look up the latest $name release from $url"
    return 1
  fi
  version="${location%/}"
  version="${version##*/}"
  version="${version#v}"
  if [[ ! "$version" =~ ^[0-9][0-9A-Za-z.+-]*$ ]]; then
    error "Latest $name release tag is not a version: $location"
    return 1
  fi
  LINUX_EXTRA_LATEST[$name]="$version"
}

# Print the expected SHA-256 of the asset: the pinned sha256.<arch> value, or
# for a tool tracking latest, its line in the release's checksums file.
linux_extra_sha256() {
  local name="$1" arch="$2" url="$3" checksums sha256
  if ! linux_extra_tracks_latest "$name"; then
    linux_extra_field "$name" "sha256.${arch}"
    return
  fi
  checksums="$(linux_extra_field "$name" checksums)" || return 1
  if ! sha256="$(curl -fsSL --retry 3 "$checksums" |
    awk -v file="${url##*/}" '$2 == file || $2 == "*" file { print $1; exit }')"; then
    error "Could not download $checksums"
    return 1
  fi
  if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
    error "$checksums has no SHA-256 for ${url##*/}"
    return 1
  fi
  printf '%s\n' "$sha256"
}

# Install one tool unless its pinned (or newest) version is already installed.
linux_install_extra() {
  local name="$1" version check expect url binary sha256 arch
  local bin
  bin="$(linux_extras_bin_dir)/${name}"
  if linux_extra_tracks_latest "$name"; then
    linux_resolve_extra_latest "$name" || return 1
  fi
  version="$(linux_extra_field "$name" version)" || return 1
  check="$(linux_extra_field "$name" check)" || return 1
  expect="$(linux_extra_field "$name" expect)" || return 1

  if linux_extra_has_version "$bin" "$check" "$expect"; then
    success "$name $version is already installed"
    return 0
  fi

  arch="$(linux_extras_arch)" || return 1
  url="$(linux_extra_field "$name" url)" || return 1
  binary="$(linux_extra_field "$name" binary)" || return 1
  if ! command_exists curl || ! command_exists sha256sum || ! command_exists tar; then
    error "curl, sha256sum, and tar are required to install $name; run: dot setup"
    return 1
  fi
  sha256="$(linux_extra_sha256 "$name" "$arch" "$url")" || return 1
  linux_fetch_extra "$name" "$url" "$sha256" "$binary" "$bin" || return 1
  if ! linux_extra_has_version "$bin" "$check" "$expect"; then
    error "Installed $name does not report $expect"
    return 1
  fi
  success "Installed $name $version at $bin"
}

# Install every tool in packages/extras.linux; keep going after a failure.
linux_install_extras() {
  local names name failed=0
  names="$(linux_extras_names)" || return 1
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    linux_install_extra "$name" || failed=1
  done <<<"$names"
  return "$failed"
}

# Read-only: warn about each missing or outdated tool and return 1 if any.
# Offline: a tool tracking latest only has to be installed and runnable;
# dot upgrade moves it to the newest release.
linux_check_extras() {
  local names name version check expect bin line failed=0
  names="$(linux_extras_names)" || return 1
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    bin="$(linux_extras_bin_dir)/${name}"
    if linux_extra_tracks_latest "$name"; then
      if ! check="$(linux_extra_field "$name" check)"; then
        failed=1
      elif ! linux_extra_version_line "$bin" "$check" >/dev/null; then
        warn "Release binary $name is not installed at ~/.local/bin/${name}"
        failed=1
      fi
      continue
    fi
    if ! version="$(linux_extra_field "$name" version)" ||
      ! check="$(linux_extra_field "$name" check)" ||
      ! expect="$(linux_extra_field "$name" expect)"; then
      failed=1
      continue
    fi
    if [[ ! -x "$bin" ]]; then
      warn "Release binary $name $version is not installed at ~/.local/bin/${name}"
      failed=1
    elif ! linux_extra_has_version "$bin" "$check" "$expect"; then
      line="$(linux_extra_version_line "$bin" "$check")" || line='no version output'
      warn "Release binary $name is outdated: want $expect, found: $line"
      failed=1
    fi
  done <<<"$names"
  return "$failed"
}

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

# Installs the release binaries (asdf among them) and puts ~/.local/bin and
# asdf shims on PATH, now and for future shells.
platform_install_runtime_manager() {
  local file failed=0

  info "Installing release binaries from packages/extras.linux"
  linux_install_extras || failed=1

  linux_path_prepend "${ASDF_DATA_DIR:-${HOME}/.asdf}/shims"
  linux_path_prepend "${HOME}/.local/bin"

  for file in "${HOME}/.bashrc" "${HOME}/.profile"; do
    if ! linux_install_hook "$file"; then
      error "Could not install the shell PATH hook in $file"
      return 1
    fi
  done
  success "Shell PATH hook is installed in ~/.bashrc and ~/.profile"
  return "$failed"
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
