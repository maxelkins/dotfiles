# Dotfiles

My macOS setup, managed with Homebrew, GNU Stow, and a small Bash `dot` command.

## Install

```sh
git clone https://github.com/maxelkins/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dot
```

Choose **Set up this Mac**, or run setup directly:

```sh
./dot setup personal
```

Setup installs Homebrew packages, Pi, and Oh My Zsh; links `home/` into `$HOME`; shares agent skills with Claude Code; and adds `dot` to `~/.local/bin`.

Restart the terminal and check the setup:

```sh
dot check
```

## Interactive menu

Run `dot` without arguments in a terminal:

```text
Dotfiles
Current package profile: personal

1) Set up this Mac
2) Upgrade everything
3) Check health
4) Apply configuration
5) Change package profile
q) Quit
```

The menu uses only Bash primitives, so fresh-machine setup has no optional UI dependency. With non-interactive input, a no-argument invocation prints help instead of waiting for a choice.

## Commands

```text
dot                         Open the interactive menu
dot setup [profile]         Set up this Mac
dot upgrade                 Upgrade repository-managed tools and configuration
dot check                   Run read-only health checks
dot apply home              Reconcile managed home links
dot apply macos             Apply macOS preferences
dot apply dock              Configure Dock applications
dot help                    Show help
```

`dot upgrade` requires a clean repository. It pulls with `--ff-only` when the current branch has an upstream, updates Homebrew packages, updates Pi in its isolated runtime, reconciles managed home links, configures repository hooks, and runs health checks. macOS preferences and Dock changes remain opt-in.

## Repository layout

```text
.
├── dot                  # Menu, command dispatch, and orchestration
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
├── scripts/lib/         # Reusable dot implementation
├── scripts/macos.sh     # macOS preferences
└── scripts/dock.sh      # Dock contents
```

Edit files under `home/`, not the linked copies in `$HOME`.

## Package profiles

Every machine installs `packages/bundle`. A saved profile can add `packages/bundle.personal` or `packages/bundle.work`; the `base` profile adds neither. The selection is local machine state at `~/.config/mac-setup/profile`.

Setup asks for a profile when needed, accepts one directly, and the interactive menu can change it:

```sh
./dot setup work
```

After changing the profile from the menu, run `dot upgrade` to reconcile its packages. The work profile leaves JetBrains Mono Nerd Font, GitHub Desktop, and Obsidian to external management. `packages/trusted-formulae` records approved third-party formulae.

## Pi runtime

Pi has its own asdf runtime under `~/.config/pi-runtime`. Its tracked `.tool-versions` selects Node independently of the current project, and the tracked `~/.local/bin/pi` launcher asks asdf for that runtime before invoking Pi. No asdf installation path is hard-coded.

`dot setup` installs Pi, `dot upgrade` updates it, and `dot check` verifies it. Pi's `/update` command also checks for a newer Node release in the configured major version. It asks before updating the tracked `.tool-versions` file and requires a Pi restart when the runtime changes.

## Existing files and backups

Before applying managed links, `dot apply home` checks each managed path. It moves conflicts to:

```text
~/.local/state/mac-setup/backups/<timestamp>/home/
```

The backup keeps paths relative to `$HOME`. Stow links files one by one so application caches and other runtime files do not enter the repository.

Pi reads skills from `~/.pi/agent/skills` and `~/.agents/skills`. Setup archives identical copies from the old Pi-specific directory. It leaves differing copies alone and prints a warning. To archive those differing copies too, run:

```sh
dot apply home --archive-legacy-skills
```

The option also works with `dot setup`.

## Manual macOS changes

Setup and upgrade do not change macOS preferences or the Dock. Apply them explicitly when wanted:

```sh
dot apply macos
dot apply dock
```

`dot apply macos` also asks for the computer name.

Thanks to [dmmulroy](https://github.com/dmmulroy/.dotfiles) for the original inspiration.
