# Repository instructions

This repository sets up a home directory on macOS and on Debian/Ubuntu Linux agent boxes with one Bash script, `dot`, and GNU Stow.

## Working rules

- Treat `home/` as a mirror of `$HOME`. For example, edit `home/.config/starship.toml` for `~/.config/starship.toml`.
- Keep machine state, credentials, sessions, caches, and generated files out of `home/`. Add a narrow `.gitignore` rule when a tool writes runtime files beside tracked configuration.
- Keep `dot` a single, readable file. Prefer a list in `packages/` and a few plain lines over a new abstraction. It must stay bash 3.2 compatible, because macOS runs it with `/bin/bash`.
- Packages: Homebrew in `packages/bundle`, plus `bundle.personal` and `bundle.work` for profiles. apt in `packages/bundle.linux`. Linux tools that apt lacks or ships too old go in `packages/install.linux`, as one line each: `<command> <install command>`.
- Skills you write go in `home/.agents/skills/`. Install third-party skills with the skills CLI (see README) so they land in `home/.agents/.skill-lock.json`; do not commit their files. Preserve changes to that lock file, because the CLI writes it outside agent tasks.
- Pi owns `~/.pi/agent/settings.json`. `templates/pi/settings.json` is only the first-run copy.
- Claude Code owns `~/.claude/settings.json`. `templates/claude/settings.json` is only the first-run copy.
- Keep `home/.pi/agent/extensions/herdr-agent-state.ts` tracked but generated. Update it with Herdr's integration installer, not by hand.
- Use asdf for runtimes. Never pin asdf itself in the repo-root `.tool-versions`.
- `dot macos` and `dot dock` change host state. Run them only when asked.

## Commits

- Use Conventional Commits.

## Verification

After changing `dot` or `scripts/`, run:

```sh
bash -n dot scripts/*.sh && shellcheck dot scripts/*.sh
```
