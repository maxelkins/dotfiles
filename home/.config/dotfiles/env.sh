# shellcheck shell=sh
# Managed by dot. Puts user-local commands and asdf shims on PATH.
# Sourced from ~/.bashrc and ~/.profile on Linux; POSIX sh, safe to source
# repeatedly and harmless on macOS. ~/.local/bin ends up ahead of the shims so
# wrappers such as ~/.local/bin/pi win over asdf shims, as in ~/.zshrc.

dot_env_prepend_path() {
  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}

dot_env_prepend_path "${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
dot_env_prepend_path "$HOME/.local/bin"
unset -f dot_env_prepend_path
export PATH
