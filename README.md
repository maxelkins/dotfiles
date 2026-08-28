# Mac setup

Personal macOS configuration managed with Homebrew, GNU Stow, and the `dot` command.

## Install

```sh
git clone https://github.com/maxelkins/mac-setup.git ~/.dotfiles
cd ~/.dotfiles
./dot init
```

`dot init` installs Homebrew packages and Oh My Zsh, links the files under `home/` into your home directory, exposes shared agent skills to Claude Code, and links `dot` through `~/.local/bin`.

Restart the terminal, then verify the installation:

```sh
dot doctor
```

## Layout

```text
.
├── dot                 # Setup and maintenance CLI
├── home/               # Mirrors paths under $HOME
│   ├── .agents/        # Shared agent skills
│   ├── .config/        # Application configuration
│   ├── .pi/            # Safe Pi configuration
│   └── Library/        # macOS application support files
├── packages/bundle     # Homebrew formulae and casks
├── scripts/lib/        # CLI implementation
├── scripts/macos.sh    # macOS preferences
├── scripts/dock.sh     # Dock contents
└── tests/              # Tests that use a temporary HOME
```

Edit tracked configuration under `home/`. GNU Stow creates the corresponding links under `$HOME`.

## Commands

```text
dot init                 Install packages and configuration
dot stow                 Refresh managed links
dot doctor               Check tools, packages, and links
dot update               Pull, update packages, and restow
dot packages install     Install the Homebrew bundle
dot packages check       Check the Homebrew bundle
dot macos                Apply macOS preferences
dot dock                 Configure Dock applications
dot edit                 Open the repository in $EDITOR
```

Run `dot help` for the current command list.

## Existing files and backups

Before Stow runs, `dot stow` checks every managed path. Conflicting files and links move to:

```text
~/.local/state/mac-setup/backups/<timestamp>/home/
```

The backup keeps each path relative to `$HOME`. Stow then links individual files instead of folding whole directories, so application runtime state stays outside the repository.

## Deliberate setup steps

`dot init` does not change macOS preferences or Dock contents. Run `dot macos` and `dot dock` explicitly because both commands change visible system state. `dot macos` also prompts for the computer name.

## Development

Run the smoke test without touching your real home directory:

```sh
bash tests/smoke.sh
```

Run syntax checks separately when changing shell scripts:

```sh
bash -n dot scripts/*.sh scripts/lib/*.sh tests/*.sh
```
