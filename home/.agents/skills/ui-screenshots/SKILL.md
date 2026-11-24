---
name: ui-screenshots
description: 'Before/after/diff screenshots of a web UI change, captured with Playwright as one markdown table per visual change. Use when asked for screenshots or a visual diff of a UI change.'
---

# ui-screenshots

`scripts/capture.mjs` renders the same pages from a **before** server (the base ref) and an **after** server (the working tree), diffs each pair pixel by pixel, and writes the tables. Everything is driven by one JSON spec.

## Steps

1. **Serve before and after.** The after is the working tree's server. For the before, check out the base ref beside it and serve it on another port:

   ```sh
   git worktree add "${TMPDIR:-/tmp}/ui-before" <base-ref>   # usually origin/main
   ```

   Give both the same data, env, and build mode; a production preview build (`build` then `preview`) is best, since it drops dev overlays and HMR. Start the second server once the first responds: some dev servers bind a fixed side port (the Cloudflare adapter's inspector on 9229) and crash when both start together. Done when both URLs return the page you will shoot.

2. **Shots.** One per visual change, named for what a reviewer sees ("Settings cards", not "index.css"), clipped to the changed component with `selector`. A padding or border change shifts everything below it, and clipping keeps that shift out of the diff. Add a **control** shot of an unaffected page when you want proof the change stayed local. Done when every visual change has a shot.

3. **Variants.** A single variant (light, desktop) is the default. Add a matrix to the shots that call for it, with per-shot `themes` / `viewports`, or when the user asks:
   - colours, theme tokens, or a dark-mode rule → `"themes": ["light", "dark"]`
   - layout, breakpoints, or responsive rules → `"viewports": ["desktop", "mobile"]`

   - a bug that only shows in one engine (Safari layout, Firefox form controls) → `"browsers": ["webkit"]` or `["chromium", "webkit"]`. A shot with one non-default engine should say so in its `name` or `caption`, for example "Radio group after failed validation (WebKit)", so the PR makes it obvious.

   Each variant adds three images, so the matrix goes only where it shows something new. Every added engine multiplies the images again, so use `browsers` only for engine-specific bugs.

4. **Capture.** Write the spec (below) beside the output directory, then run from the project root so the project's own Playwright is used:

   ```sh
   node ~/.agents/skills/ui-screenshots/scripts/capture.mjs spec.json
   ```

   Stdout is the output directory (`$OUT`); progress goes to stderr. Done when it exits 0.

5. **Check.** Read every `*-diff.png` that `screenshots.md` references. Red marks changed pixels over a faded copy of the after image. Done when the red is confined to the changed component; content shifted inside it is expected. Red elsewhere is **noise** (a clock, a random avatar, an animation, a dev overlay): `mask` it, `wait` it out, or tighten `selector`, then rerun.

6. **Clean up.** Stop both servers and `git worktree remove "${TMPDIR:-/tmp}/ui-before"`. Done when both ports are free.

Hand `screenshots.md` to the user, or to the `pr-screenshots` skill for a pull request.

## Output

`$OUT` defaults to `$TMPDIR/ui-screenshots/<project>-<timestamp>/`, outside the repo; a path inside the repo must be git-ignored first. A rerun replaces the files the script generates and keeps any others.

- `<shot>[-<browser>][-<theme>][-<viewport>]-{before,after,diff}.png`
- `screenshots.md`: the tables, with `./` image paths, usable directly as a `gh --body-file`.
- `attach.txt`: exactly the images `screenshots.md` references, one per line.
- `manifest.json`: every shot and variant with `changedPercent`, `sizeChanged`, or `error`.

A shot with no change in any variant is reported on stderr as "No visual change" and left out of `screenshots.md`. For a control shot that is the expected result; for any other shot, its page or `selector` is wrong.

## Table template

`capture.mjs` emits exactly this, so change the two together. The caption line appears only when the shot has a `caption`.

Single variant:

```markdown
### <Change name>

<Optional one-line caption.>

| Before | After | Diff |
| --- | --- | --- |
| ![Before](./<shot>-before.png) | ![After](./<shot>-after.png) | ![Diff](./<shot>-diff.png) |
```

Several variants, one row each, labelled with only the parts that vary:

```markdown
### <Change name>

<Optional one-line caption.>

| Variant | Before | After | Diff |
| --- | --- | --- | --- |
| Light · Desktop | ![Before](./<shot>-light-desktop-before.png) | ![After](./<shot>-light-desktop-after.png) | ![Diff](./<shot>-light-desktop-diff.png) |
| Dark · Mobile | ![Before](./<shot>-dark-mobile-before.png) | ![After](./<shot>-dark-mobile-after.png) | ![Diff](./<shot>-dark-mobile-diff.png) |
```

With several engines the label and stem lead with the engine, for example `WebKit · Dark` and `<shot>-webkit-dark-desktop-before.png`. As with themes and viewports, the engine appears only when more than one is in play for that shot; a WebKit-only shot keeps the plain names.

A variant with no change keeps its row with `_No visual change_` in the Diff cell. Images use `![alt](./file.png)` because that is the form `gh --attach` rewrites to uploaded URLs.

## Spec

```json
{
  "before": "http://localhost:4001",
  "after": "http://localhost:3000",
  "out": "/tmp/ui-screenshots/my-branch",
  "shots": [
    {
      "name": "Settings cards",
      "caption": "Cards are rounded and stack on mobile.",
      "path": "/settings",
      "selector": ".settings-grid",
      "themes": ["light", "dark"],
      "viewports": ["desktop", "mobile"]
    },
    { "name": "Save button", "path": "/settings", "selector": "form .actions", "actions": [{ "hover": "button[type=submit]" }] }
  ]
}
```

Top level:

- `before`, `after` (required): base URLs; each shot's `path` is appended as-is.
- `shots` (required), `out`.
- `themes`, `viewports`, `browsers`: the default matrix for every shot. Default `["light"]`, `["desktop"]` and `["chromium"]`. `browsers` accepts only `chromium`, `firefox` and `webkit`; anything else is an error.
- `mask`: selectors painted over in both images.
- `deviceScaleFactor` (default 1; 2 for fine detail), `fullPage` (default false).
- `localStorage`, `initScript`: applied before page scripts in every variant.
- `threshold` (default 10): how far an RGBA channel (0–255) may differ before a pixel counts as changed. 10 ignores antialiasing. Lower it for a subtle colour shift the diff misses; raise it when scattered red specks appear in unaffected areas.

Per shot:

- `name` (required): the heading and file-name stem.
- `path` (default `/`), `caption`, `fullPage`, `mask`, `themes`, `viewports`, `browsers` (overrides the top-level list).
- `selector`: clip to its **first** match; select a container to capture several items.
- `actions`: run in order after load, identically on both servers. Each is one of `{"click": sel}`, `{"hover": sel}`, `{"fill": [sel, text]}`, `{"press": "Escape"}`, `{"waitFor": sel}`, `{"wait": ms}`, `{"eval": "js"}`.
- `waitFor` (selector), `wait` (ms): before the screenshot.

Themes: `"light"` and `"dark"` emulate `prefers-color-scheme`. A site with a manual toggle needs a theme object: `{ "name": "dark", "colorScheme": "dark", "localStorage": { "theme": "dark" }, "attributes": { "data-theme": "dark" } }`, plus `initScript` for anything else. `attributes` go on `<html>`, set before load and again after it.

Viewports: `desktop` 1280×800, `tablet` 768×1024, `mobile` 390×844, or `{ "name", "width", "height" }`.

Browsers: `chromium`, `firefox`, `webkit`. The diff always runs on Chromium, since it only compares PNGs. Caveats:

- Playwright's WebKit on Linux is not Safari. Say so wherever a WebKit-only shot is the evidence.
- Firefox does not support `isMobile` or `hasTouch`; the script sets only width and height, but any device emulation added later must allow for that.
- Fonts and antialiasing differ between engines, so compare only the same engine before and after, never across engines. The matrix guarantees this.

The script already freezes animations and hides the Astro, Vite, Next.js and webpack dev overlays. `mask` cannot reach inside shadow DOM, so remove any other overlay with `{"eval": "document.querySelector('<host>')?.remove()"}`.

## Running node

When the project has no Playwright, the script installs it once into `${XDG_CACHE_HOME:-~/.cache}/ui-screenshots`, and prints the install command (`... install <engine>`) for the engine that is missing. Under asdf, `node` outside a project fails with "No version is set": run from the project root.
