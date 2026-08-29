# Repository instructions

This repository manages a macOS home directory with GNU Stow.

## Working rules

- Treat `home/` as a mirror of `$HOME`. For example, edit `home/.config/starship.toml` for `~/.config/starship.toml`.
- Keep machine state, credentials, sessions, caches, and generated files outside `home/`. Add a narrow `.gitignore` rule when a managed tool writes runtime files beside tracked configuration.
- Preserve user changes in `home/.agents/.skill-lock.json`. Skill installers may update it outside an agent task.
- Keep `home/.pi/agent/extensions/herdr-agent-state.ts` tracked but generated. Update it through Herdr's integration installer rather than editing it by hand.
- Put shared Homebrew declarations in `packages/bundle`, personal declarations in `packages/bundle.personal`, and work declarations in `packages/bundle.work`.
- Record any intentional third-party Homebrew trust at formula scope in `packages/trusted-formulae`.
- Treat `~/.config/mac-setup/profile` as local machine state. Package commands read it to select one optional bundle.
- Keep `dot` limited to command dispatch. Put reusable behavior in `scripts/lib/` and explicit macOS mutations in `scripts/`.
- Use `dot stow` for managed links. Its preflight backs up conflicts before GNU Stow runs.
- Keep `dot macos` and `dot dock` opt-in. They change host state.

## Verification

After shell or layout changes, run:

```sh
bash -n dot scripts/*.sh scripts/lib/*.sh
```
