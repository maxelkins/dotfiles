# Dotfiles

My macOS and Linux agent-box setup: Homebrew or apt, GNU Stow, and one Bash script, `dot`.

Thanks to [dmmulroy](https://github.com/dmmulroy/.dotfiles) for the original inspiration.

## Install

macOS:

```sh
git clone https://github.com/maxelkins/dotfiles.git ~/.dotfiles
~/.dotfiles/dot setup personal   # or: base, work
```

Linux (Debian/Ubuntu, as a user with sudo):

```sh
sudo apt-get install -y git
git clone https://github.com/maxelkins/dotfiles.git ~/.dotfiles
~/.dotfiles/dot setup
```

Open a new shell, then run `dot check`.

## Commands

```text
dot setup [base|personal|work]  Install packages, tools, Pi, skills, and links
dot update                      Pull this repo, then upgrade everything
dot check                       Report anything setup has not done
dot link                        Link home/ into $HOME
dot macos                       Apply macOS preferences (opt-in)
dot dock                        Set up the Dock (opt-in)
```

`dot --headless <command>` (or `DOT_HEADLESS=1`) never prompts. Use it for unattended agent boxes, with passwordless sudo.

## Layout

```text
dot                     The whole tool
home/                   Mirror of $HOME, linked with GNU Stow
packages/
  bundle                Brewfile for every Mac
  bundle.personal       Extra Brewfile for the personal profile
  bundle.work           Extra Brewfile for the work profile
  bundle.linux          apt packages
  install.linux         Linux tools apt lacks: <command> <install command>
scripts/macos.sh        macOS preferences (dot macos)
scripts/dock.sh         Dock layout (dot dock)
templates/claude/       Claude Code settings copied once, then owned by Claude Code
templates/pi/           Pi files copied once, then owned by Pi
```

## How it works

- **Links.** `dot link` (also run by setup and update) links every file under `home/` into `$HOME`. Anything already in the way moves to `~/.local/state/dotfiles/backups/<timestamp>/`. `home/Library/` is not linked on Linux.
- **Profiles (macOS).** `dot setup work` saves `work` to `~/.config/dotfiles/profile`. Every Mac installs `packages/bundle`, plus `bundle.<profile>` unless the profile is `base`.
- **Linux tools.** Setup runs each line of `packages/install.linux` whose command is missing; update runs them all again. `install_release` in `dot` downloads the latest GitHub or GitLab release.
- **Shell.** macOS uses zsh with Oh My Zsh. Linux keeps bash. Setup adds one line to the top of `~/.bashrc` and `~/.profile` that loads `~/.config/dotfiles/env.sh`, so `~/.local/bin` and asdf shims are on `PATH` even for non-interactive SSH commands.
- **Local shell config.** `~/.zshrc` sources `~/.zshrc.local` when it exists. Keep machine-specific or work-only settings there.

## Pi

Pi runs on its own Node, pinned in `home/.config/pi-runtime/.tool-versions`, so a project's `.tool-versions` cannot swap it out. `~/.local/bin/pi` starts it with that Node. `dot setup` and `dot update` install the latest Pi.

Pi owns `~/.pi/agent/settings.json` and `~/.pi/agent/mcp.json`. Setup copies `templates/pi/settings.json` and `templates/pi/mcp.example.json` there only when they don't exist yet. After that, change settings in Pi.

## Skills

Skills I wrote live in `home/.agents/skills/` and are linked like any other config, including into `~/.claude/skills`.

Third-party skills are not committed. `home/.agents/.skill-lock.json` lists them. Setup installs any that are missing with the [skills CLI](https://github.com/vercel-labs/skills), for Pi and Claude Code, and update upgrades them. To add one:

```sh
npx skills add <owner/repo> --global --skill <name> --agent pi claude-code
```

The CLI updates the lock file through its link, so commit the change.

## Development

```sh
npm install           # also points Git at .githooks (Prettier on commit)
npm run format:check
npm run typecheck:pi
shellcheck dot scripts/*.sh
```

CI runs the same checks.
