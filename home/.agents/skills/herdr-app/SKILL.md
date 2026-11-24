---
name: herdr-app
description: "Herdr desktop app and herdr-core (`herdr-app`, `hc`). Use when the user mentions the Herdr app or herdr-core; asks to change its window (spaces, tabs, panes, layouts, themes, settings, keys, mods); or asks to start, read, message or wait on its terminals. Applies when HC_TERMINAL_ID is set. The older `herdr` CLI (HERDR_ENV=1) is the herdr skill."
---

# Herdr desktop app

The app ships its own agent manuals, which change with each release. Read the
current ones before acting:

```sh
herdr-app --skill   # anything the person sees: spaces, tabs, panes, layouts, looks, mods
hc --skill          # anything that runs: start, read, message, wait on terminals
```

Read both when a task crosses the two.

The app's home is `~/.config/herdr-app` (or `$HERDR_APP_HOME`). Its
`AGENTS.md` is the full guide to settings, layouts, themes, keys and mods;
read it before editing files there.

To keep a change to `~/.config/herdr-app`, make it in
`~/dev/dotfiles/home/.config/herdr-app/` and follow that repo's `AGENTS.md`
(link with `dot stow`).

Done when `herdr-app status` shows an empty `errors` list, and, for a visual
change, a `herdr-app shot` you have looked at shows the change.
