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
- Copy app config directories for Karabiner, Ghostty, etc.
- Apply macOS system preferences

**Restart your terminal** for all changes to take effect.

## Customizing

- Edit files in `dotfiles/` to change your shell, git, or app config.
- Edit `scripts/macos.sh` to tweak macOS settings.
- Add/remove Homebrew packages in `Brewfile`.

## Notes

- Existing dotfiles are backed up as `*.bak` before being replaced.
- App config directories are copied, not symlinked, for compatibility.
