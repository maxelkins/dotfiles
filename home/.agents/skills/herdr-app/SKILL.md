---
name: herdr-app
description: "Drive the Herdr desktop app and its herdr-core terminals (`herdr-app`, `hc`). Use when the user mentions the Herdr app or herdr-core, or asks to change its window: spaces, tabs, panes, layouts, themes, settings, keys or mods; or to start, read, message or wait on agents and programs in it. Applies when HC_TERMINAL_ID is set; the older `herdr` CLI (HERDR_ENV=1) is the herdr skill."
---

# Herdr desktop app

The app ships its own agent manuals, and they change with each release. Read
the current ones before acting rather than working from memory:

```sh
herdr-app --skill   # the window: spaces, tabs, panes, layouts, looks, mods
hc --skill          # herdr-core: start, read, message and wait on terminals
```

Read `herdr-app --skill` for anything the person sees, and `hc --skill` for
anything that runs. Read both when a task crosses the two.

The app's home is `~/.config/herdr-app` (or `$HERDR_APP_HOME`). Its
`AGENTS.md` is the full guide to settings, layouts, themes, keys and mods;
read it before editing files there.

To keep a change to `~/.config/herdr-app`, make it in
`~/dev/dotfiles/home/.config/herdr-app/` and follow that repo's `AGENTS.md`
(link with `dot stow`).

Done when the change shows in `herdr-app status` with an empty `errors`
list, and in a `herdr-app shot` you have looked at when the change is visual.
