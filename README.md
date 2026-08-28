# Mac Setup

Automate macOS development environment setup, dotfiles, and app and system preferences.

## Usage

```sh
bash setup.sh
```

This will:

- Install Homebrew and all packages/casks from `Brewfile`
- Install Oh My Zsh
- Symlink top-level dotfiles and standalone `~/.config` files (e.g. `.zshrc`, `.gitconfig`, `starship.toml`)
- Symlink Herdr's `config.toml` while leaving logs, plugins, sessions, and runtime state local
- Symlink the tracked agent skills to `~/.agents/skills` and expose them to Claude Code while preserving Claude-only skills
- Symlink safe Pi settings, extensions, the Cobalt2 theme, and Zentui configuration while leaving auth and sessions private
- Copy app config directories for Karabiner, Ghostty, etc.
- Apply macOS system preferences
- Install the repository's staged-secret pre-commit check

**Restart your terminal** for all changes to take effect.

## Customizing

- Edit files in `dotfiles/` to change your shell, git, or app config.
- Edit `scripts/macos.sh` to tweak macOS settings.
- Add/remove Homebrew packages in `Brewfile`.

## Agent skills

Shared skills live under `dotfiles/agents/skills/`. Setup links that directory to
`~/.agents/skills`, links the Skills CLI lock file, and adds per-skill links under
`~/.claude/skills`. Claude-only skills already present in that directory are left
untouched. Pi and other Agent Skills-compatible tools read `~/.agents/skills`
directly.

## Pi appearance

Pi uses the native `cobalt2` theme from `dotfiles/pi/agent/themes/`, a compact
welcome card from `dotfiles/pi/agent/extensions/`, and the `pi-zentui` package
for a responsive Starship-style footer and Opencode editor metadata showing
model, provider, and thinking effort. Safe Pi settings and global agent
instructions are tracked under `dotfiles/pi/agent/`; authentication and session
data are not.

## Secret handling

Tracked files may contain 1Password references such as `op://vault/item/field`, but never resolved values. Put raw shell secrets in `~/.zshrc.secrets`; the tracked `.zshrc` loads that file when it exists. Git ignores common credential files, and `dotfiles/pi/agent/.gitignore` allows only the Pi files reviewed for publication. Review that allowlist before adding another Pi path.

`setup.sh` installs Gitleaks and sets `core.hooksPath` to the versioned hooks in `.githooks`. The pre-commit hook scans the staged patch. Run it directly when investigating a finding:

```sh
gitleaks git --staged --redact --verbose --config .gitleaks.toml
```

Fix a real finding before committing. For a false positive, add the narrowest practical exception to `.gitleaks.toml` and include that change in review. If a commit cannot wait, `SKIP_GITLEAKS=1 git commit` is the explicit bypass. Record why it was needed in the pull request. CI still scans the full checked-out history.

If a credential reaches Git, revoke or rotate it first. Then remove it from history if needed and scan again. Rewriting the repository does not remove copies held by forks, caches, or existing clones, so treat the old credential as compromised even after cleanup.

GitHub secret scanning and push protection should also be enabled in the repository's Code security settings when available.

## Nerd Font fallback

Starship uses Nerd Font icons. Ghostty keeps Monaco as its primary font and uses
JetBrains Mono Nerd Font Mono for missing glyphs. In iTerm2, enable **Use a
different font for non-ASCII text** under **Profiles → Text** and select
**JetBrainsMonoNL Nerd Font Mono**.

## Notes

- Existing dotfiles are backed up as `*.bak` before being replaced.
- App config directories are copied, not symlinked, for compatibility.
