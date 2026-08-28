#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="${TEST_ROOT}/home"
FAKE_BIN="${TEST_ROOT}/bin"
BACKUPS="${TEST_ROOT}/backups"
mkdir -p "$TEST_HOME/.oh-my-zsh" "$FAKE_BIN"

cat > "${FAKE_BIN}/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  bundle) exit 0 ;;
  update) exit 0 ;;
  *) exit 0 ;;
esac
FAKE_BREW

cat > "${FAKE_BIN}/stow" <<'FAKE_STOW'
#!/usr/bin/env bash
set -euo pipefail
root=""
target=""
while (( $# > 0 )); do
  case "$1" in
    --dir) root="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --restow|--no-folding) shift ;;
    home) shift ;;
    *) printf 'unexpected stow argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done
[[ -n "$root" && -n "$target" ]]
while IFS= read -r source; do
  relative="${source#${root}/home/}"
  destination="${target}/${relative}"
  mkdir -p "$(dirname "$destination")"
  rm -f "$destination"
  ln -s "$source" "$destination"
done < <(find "${root}/home" -type f | LC_ALL=C sort)
FAKE_STOW

chmod +x "${FAKE_BIN}/brew" "${FAKE_BIN}/stow"

export HOME="$TEST_HOME"
export DOT_BACKUP_ROOT="$BACKUPS"
export PATH="${FAKE_BIN}:$PATH"

printf 'old zsh config\n' > "$HOME/.zshrc"

"$ROOT/dot" help >/dev/null
if "$ROOT/dot" unknown >/dev/null 2>&1; then
  printf 'unknown command unexpectedly succeeded\n' >&2
  exit 1
fi

"$ROOT/dot" stow >/dev/null
[[ -L "$HOME/.zshrc" ]]
[[ "$HOME/.zshrc" -ef "$ROOT/home/.zshrc" ]]
backup_zshrc="$(find "$BACKUPS" -path '*/home/.zshrc' -type f -print -quit)"
[[ -n "$backup_zshrc" ]]
grep -Fqx 'old zsh config' "$backup_zshrc"
[[ -L "$HOME/.claude/skills/diagnose" ]]
[[ "$HOME/.claude/skills/diagnose" -ef "$HOME/.agents/skills/diagnose" ]]

"$ROOT/dot" stow >/dev/null
"$ROOT/dot" doctor >/dev/null
"$ROOT/dot" link >/dev/null
[[ -L "$HOME/.local/bin/dot" ]]
"$ROOT/dot" unlink >/dev/null
[[ ! -e "$HOME/.local/bin/dot" && ! -L "$HOME/.local/bin/dot" ]]

printf 'smoke test passed\n'
