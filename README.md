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
dot skills update           Update vendored skills and reconcile home links
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
│   ├── .agents/         # Shared agent skills and global agent rules
│   ├── .claude/         # Claude Code adapter for the shared rules
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

### Local MCP connections

Pi's `~/.pi/agent/mcp.json` is a local file, not a managed symlink: server URLs can contain credentials. `dot apply home` (also run by setup and upgrade) copies `templates/pi/mcp.example.json` there only if no local configuration exists. Existing files and symlinks are never overwritten. Edit the local file to configure and enable servers, then run `/reload` in Pi.

Commit only the credential-free example. `home/.pi/agent/mcp.json` is ignored as a safeguard against accidentally putting the live configuration back into the managed tree.

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

Global agent rules live in `home/.agents/AGENTS.md`. Each harness reads that one file through a thin adapter:

- Pi: `home/.pi/agent/AGENTS.md` is a symlink to it.
- OpenCode: `home/.config/opencode/opencode.jsonc` lists it under `instructions`.
- Claude Code: `home/.claude/CLAUDE.md` imports it with `@~/.agents/AGENTS.md`.

Keep harness-specific guidance in the harness's own config and repository-specific rules in that repository's `AGENTS.md`.

## Skill updates

Run `dot skills update` to download the latest default-branch versions of skills
listed in `packages/skills.json`, update their copies under `home/.agents/skills/`,
and reapply managed links. Requires Git and Python 3.9+. Review `git diff` before
committing, then run `/reload` in Pi. This is explicit, not part of `dot upgrade`.

The updater skips skills with uncommitted files and reports failures without
preventing other skills from updating. Commit newly installed skills before their
first update. Skills without a source entry are reported and left alone (including
local/custom skills). Upstream code is downloaded, never executed; review the new
instructions before using them.

Each manifest entry maps the installed directory name to `sourceUrl` and
`skillPath` (the repository-relative path to its `SKILL.md`). Successful updates
record the source commit in `revision`. Register new third-party skills here after
installing them into `home/.agents/skills/`. Installer lockfiles are not modified;
the source manifest stays outside `home/` so it is not linked into `$HOME`.

`home/.agents/.skill-lock.json` belongs to the skill installer and records its install-time hashes and metadata. `dot skills update` does not refresh those hashes; `packages/skills.json` records the revisions fetched by this updater. The vendored files in Git remain the exact installed snapshot; the manifest is provenance, not a lockfile-driven restore command. No additional lockfile is needed.

Vendored skills are excluded from Prettier to preserve upstream formatting. Run the repository's local checks with:

```sh
npm test
npm run format:check
npm run typecheck:pi
```

Upstream skill tests are not part of `npm test`: some depend on their original monorepo. In particular, Plannotator's Mermaid rendering test requires its `packages/ui` workspace and dependencies; run that integration test in an upstream checkout with those dependencies installed.

## Local shell configuration

`~/.zshrc` optionally sources `~/.zshrc.local` when readable. Keep machine-specific or work-only configuration there, outside this repository. For example, put a guarded `source` of your work environment script in that local file rather than adding its path to the shared shell configuration. Setup never creates or overwrites it.

## Manual macOS changes

Setup and upgrade do not change macOS preferences or the Dock. Apply them explicitly when wanted:

```sh
dot apply macos
dot apply dock
```

`dot apply macos` also asks for the computer name.

Thanks to [dmmulroy](https://github.com/dmmulroy/.dotfiles) for the original inspiration.
