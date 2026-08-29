# Dotfiles

macOS development configuration managed with Homebrew, GNU Stow, and the `dot` command.

## Install

```sh
git clone https://github.com/maxelkins/dotfiles.git ~/.dotfiles
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
├── packages/
│   ├── bundle          # Packages shared by every machine
│   ├── bundle.personal # Personal applications
│   ├── bundle.work     # Work applications
│   └── trusted-formulae # Narrow trust for third-party formulae
├── scripts/lib/        # CLI implementation
├── scripts/macos.sh    # macOS preferences
├── scripts/dock.sh     # Dock contents
└── tests/              # Tests that use a temporary HOME
```

Edit tracked configuration under `home/`. GNU Stow creates the corresponding links under `$HOME`.

## Commands

```text
dot init [options]       Install packages and configuration
dot stow [options]       Refresh managed links
dot doctor               Check tools, packages, and links
dot update               Pull repo, update Homebrew packages, and restow
dot packages install     Install Homebrew packages for the selected profile
dot packages check       Check Homebrew packages for the selected profile
dot profile show         Show the saved package profile
dot profile set P        Select base, personal, or work packages
dot macos                Apply macOS preferences
dot dock                 Configure Dock applications
dot edit                 Open the repository in $EDITOR
```

Run `dot help` for the current command list.

## Package profiles

Every machine installs `packages/bundle`. One saved profile adds either `packages/bundle.personal` or `packages/bundle.work`; choose `base` to install neither optional bundle.

Every interactive `dot init` asks for `base`, `personal`, or `work`, using the saved profile as its default. Press Enter to keep the current selection. For unattended setup, pass the choice explicitly:

```sh
./dot init --profile work
```

The selection is stored outside the repository at `~/.config/mac-setup/profile`. Change it with `dot profile set personal`. Package installation, checks, updates, and `dot doctor` reuse the saved selection.

The work profile treats JetBrains Mono Nerd Font, GitHub Desktop, and Obsidian as externally managed. Their Homebrew casks remain in the personal profile. Formulae listed in `packages/trusted-formulae` receive narrow, formula-level Homebrew trust before installation.

A failed package does not prevent shell configuration and Stow links from being applied. `dot init` finishes those steps, reports the incomplete package installation, and exits nonzero so the failure remains visible.

## Existing files and backups

Before Stow runs, `dot stow` checks every managed path. Conflicting files and links move to:

```text
~/.local/state/mac-setup/backups/<timestamp>/home/
```

The backup keeps each path relative to `$HOME`. Stow then links individual files instead of folding whole directories, so application runtime state stays outside the repository.

Pi loads skills from both `~/.pi/agent/skills` and `~/.agents/skills`. Setup automatically archives identical legacy copies from the Pi-specific directory. If a legacy copy differs from the repo version, setup preserves it and prints a warning. To archive all conflicting legacy copies and use a fresh repo-managed set, run:

```sh
dot stow --archive-legacy-skills
```

The same option works with `dot init`.

## Deliberate setup steps

`dot init` does not change macOS preferences or Dock contents. Run `dot macos` and `dot dock` explicitly because both commands change visible system state. `dot macos` also prompts for the computer name.

## Development

Run syntax checks when changing shell scripts:

```sh
bash -n dot scripts/*.sh scripts/lib/*.sh
```

_Credit: Thanks to [dmmulroy](https://github.com/dmmulroy/.dotfiles) for the inspiration_
