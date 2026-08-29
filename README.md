# Dotfiles

My macOS setup, managed with Homebrew, GNU Stow, and a small `dot` command.

## Install

```sh
git clone https://github.com/maxelkins/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dot init
```

`dot init` installs Homebrew packages and Oh My Zsh, links the files in `home/` into `$HOME`, shares agent skills with Claude Code, and adds `dot` to `~/.local/bin`.

Restart the terminal and check the setup:

```sh
dot doctor
```

## Repository layout

```text
.
├── dot                  # Setup and maintenance command
├── home/                # Files linked into $HOME
│   ├── .agents/         # Shared agent skills
│   ├── .config/         # Application configuration
│   ├── .pi/             # Pi configuration
│   └── Library/         # macOS application support files
├── packages/
│   ├── bundle           # Packages for every machine
│   ├── bundle.personal  # Personal applications
│   ├── bundle.work      # Work applications
│   └── trusted-formulae # Approved third-party formulae
├── scripts/lib/         # dot implementation
├── scripts/macos.sh     # macOS preferences
└── scripts/dock.sh      # Dock contents
```

Edit files under `home/`, not the linked copies in `$HOME`.

## Commands

```text
dot init [options]       Install packages and configuration
dot stow [options]       Refresh managed links
dot doctor               Check tools, packages, and links
dot update               Pull changes, update packages, and restow
dot packages install     Install packages for the selected profile
dot packages check       Check packages for the selected profile
dot profile show         Show the selected profile
dot profile set P        Select base, personal, or work packages
dot macos                Apply macOS preferences
dot dock                 Set Dock applications
dot link                 Add dot to ~/.local/bin
dot unlink               Remove dot from ~/.local/bin
dot edit                 Open this repository in $EDITOR
```

Run `dot help` for the full command list.

## Package profiles

Every machine installs `packages/bundle`. A saved profile can add `packages/bundle.personal` or `packages/bundle.work`. The `base` profile adds neither.

Interactive setup asks which profile to use. Press Enter to keep the current choice, or pass one directly:

```sh
./dot init --profile work
```

The work profile leaves JetBrains Mono Nerd Font, GitHub Desktop, and Obsidian to external management. Their Homebrew casks stay in the personal profile. `packages/trusted-formulae` lists third-party formulae that Homebrew may trust during installation.

## Existing files and backups

Before Stow runs, `dot stow` checks each managed path. It moves conflicts to:

```text
~/.local/state/mac-setup/backups/<timestamp>/home/
```

The backup keeps paths relative to `$HOME`. Stow links files one by one so application caches and other runtime files do not end up in the repository.

Pi reads skills from `~/.pi/agent/skills` and `~/.agents/skills`. Setup archives identical copies from the old Pi-specific directory. It leaves differing copies alone and prints a warning.

To archive those differing copies too, run:

```sh
dot stow --archive-legacy-skills
```

The option also works with `dot init`.

## Manual macOS changes

`dot init` does not change macOS preferences or the Dock. Run `dot macos` and `dot dock` yourself when you want those changes. `dot macos` also asks for the computer name.

Thanks to [dmmulroy](https://github.com/dmmulroy/.dotfiles) for the original inspiration.
