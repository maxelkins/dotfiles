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
printf '%s\n' "$*" >> "$FAKE_BREW_LOG"
case "${1:-}" in
  bundle)
    # Homebrew may read stdin, so package iteration must not use stdin as its list.
    cat >/dev/null
    [[ "${FAKE_BREW_FAIL_BUNDLE:-0}" != "1" ]]
    ;;
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
export FAKE_BREW_LOG="${TEST_ROOT}/brew.log"
export PATH="${FAKE_BIN}:$PATH"
: > "$FAKE_BREW_LOG"

printf 'old zsh config\n' > "$HOME/.zshrc"
mkdir -p "$HOME/.pi/agent/skills/unslop" "$HOME/.pi/agent/skills/caveman"
cp "$ROOT/home/.agents/skills/unslop/SKILL.md" "$HOME/.pi/agent/skills/unslop/SKILL.md"
printf 'different local skill\n' > "$HOME/.pi/agent/skills/caveman/SKILL.md"

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
if [[ -e "$HOME/.pi/agent/skills/unslop" ]]; then
  printf 'identical legacy Pi skill was not migrated\n' >&2
  exit 1
fi
backup_unslop="$(find "$BACKUPS" -path '*/home/.pi/agent/skills/unslop/SKILL.md' -type f -print -quit)"
if [[ -z "$backup_unslop" ]]; then
  printf 'identical legacy Pi skill was not backed up\n' >&2
  exit 1
fi
grep -Fqx 'different local skill' "$HOME/.pi/agent/skills/caveman/SKILL.md"
[[ -L "$HOME/.claude/skills/diagnose" ]]
[[ "$HOME/.claude/skills/diagnose" -ef "$HOME/.agents/skills/diagnose" ]]

"$ROOT/dot" stow --archive-legacy-skills >/dev/null
if [[ -e "$HOME/.pi/agent/skills/caveman" ]]; then
  printf 'legacy Pi skill was not archived on request\n' >&2
  exit 1
fi
backup_caveman="$(find "$BACKUPS" -path '*/home/.pi/agent/skills/caveman/SKILL.md' -type f -print -quit)"
if [[ -z "$backup_caveman" ]]; then
  printf 'legacy Pi skill archive was not preserved\n' >&2
  exit 1
fi

[[ "$("$ROOT/dot" profile show)" == "base" ]]
"$ROOT/dot" profile set work >/dev/null
[[ "$("$ROOT/dot" profile show)" == "work" ]]
: > "$FAKE_BREW_LOG"
"$ROOT/dot" packages check >/dev/null
grep -Fq -- "--file=${ROOT}/packages/bundle" "$FAKE_BREW_LOG"
grep -Fq -- "--file=${ROOT}/packages/bundle.work" "$FAKE_BREW_LOG"
if grep -Fq 'bundle.personal' "$FAKE_BREW_LOG"; then
  printf 'work profile unexpectedly checked personal bundle\n' >&2
  exit 1
fi
if "$ROOT/dot" profile set invalid >/dev/null 2>&1; then
  printf 'invalid profile unexpectedly succeeded\n' >&2
  exit 1
fi

"$ROOT/dot" doctor >/dev/null
"$ROOT/dot" link >/dev/null
[[ -L "$HOME/.local/bin/dot" ]]
"$ROOT/dot" unlink >/dev/null
[[ ! -e "$HOME/.local/bin/dot" && ! -L "$HOME/.local/bin/dot" ]]

# Package failures must not prevent configuration and command links from being applied.
rm "$HOME/.zshrc"
export FAKE_BREW_FAIL_BUNDLE=1
init_output="${TEST_ROOT}/init-output.log"
if "$ROOT/dot" init >"$init_output" 2>&1; then
  printf 'init unexpectedly succeeded after a package failure\n' >&2
  exit 1
fi
unset FAKE_BREW_FAIL_BUNDLE
grep -Fq "setup completed with package failures" "$init_output"
grep -Fqx 'trust --formula grega/tap/hdi' "$FAKE_BREW_LOG"
[[ -L "$HOME/.zshrc" ]]
[[ "$HOME/.zshrc" -ef "$ROOT/home/.zshrc" ]]
[[ -L "$HOME/.local/bin/dot" ]]

grep -Fq 'cask "github"' "$ROOT/packages/bundle.personal"
if grep -Eq 'cask "(font-jetbrains-mono-nerd-font|github|obsidian)"' "$ROOT/packages/bundle"; then
  printf 'externally managed work app found in base bundle\n' >&2
  exit 1
fi

printf 'smoke test passed\n'
