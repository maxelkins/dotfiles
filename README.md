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

## Nerd Font fallback

Starship uses Nerd Font icons. Ghostty keeps Monaco as its primary font and uses
JetBrains Mono Nerd Font Mono for missing glyphs. In iTerm2, enable **Use a
different font for non-ASCII text** under **Profiles → Text** and select
**JetBrainsMonoNL Nerd Font Mono**.

## Notes

- Existing dotfiles are backed up as `*.bak` before being replaced.
- App config directories are copied, not symlinked, for compatibility.
