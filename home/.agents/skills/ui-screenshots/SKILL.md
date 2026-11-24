---
name: ui-screenshots
description: 'Capture before/after/diff screenshots of a web UI change with Playwright and emit one markdown comparison table per visual change. Use when asked for screenshots, a visual diff, or before/after images of a UI change.'
---

# ui-screenshots

Render the same pages from a **before** server (the base ref) and an **after** server (the working tree), diff them pixel by pixel, and write ready-to-paste markdown. `scripts/capture.mjs` does all of it from one JSON spec.

## Steps

1. **Serve before and after.** Run the current tree's dev server as usual (the after). For the before, check out the base ref beside it and serve it on another port:

   ```sh
   git worktree add "${TMPDIR:-/tmp}/ui-before" <base-ref>   # usually origin/main
   cd "${TMPDIR:-/tmp}/ui-before" && <install deps> && <dev server on another port>
   ```

   Both servers must use the same data, env, and build mode, or the diff shows noise. Prefer a production preview build (e.g. `build` then `preview`) on both when practical: it drops dev overlays and HMR. Start the second server only after the first responds: some dev servers bind a fixed side port (e.g. the Cloudflare adapter's inspector on 9229) and crash if both start at once. Done when both URLs return the page you will shoot.
2. **Choose the shots**: one per visual change, named for the change a reviewer sees ("Settings cards", not "index.css"). Clip each to the changed component with `selector`: a padding or border change shifts everything below it, and an unclipped diff paints the whole page red. `selector` clips to the **first** match only; to capture several items, select their container.
3. **Choose the variants. Single variant by default**: no `themes` or `viewports` in the spec. Add a matrix when the user asks, or when the change calls for it:
   - colours, theme tokens, or anything inside a dark-mode rule → `"themes": ["light", "dark"]`
   - layout, breakpoints, or responsive rules → `"viewports": ["desktop", "mobile"]`

   Images multiply (shots × themes × viewports × 3), so put the matrix on the shots that need it, with per-shot `themes`/`viewports`, rather than at the top level.
4. **Write the spec** (schema below) outside the repo, next to the output, and run from the project root, so the project's own Playwright is used when it has one:

   ```sh
   node ~/.agents/skills/ui-screenshots/scripts/capture.mjs spec.json
   ```

   It prints the output directory on stdout and progress on stderr, and exits non-zero if any shot failed.
5. **Check the result.** Read every `*-diff.png` referenced in `screenshots.md`. Red marks changed pixels over a faded copy of the after image. Done when the red is confined to the changed component or region; content that shifted inside it is expected. Red outside it is noise (a clock, a random avatar, an animation, a dev overlay) to `mask`, `wait` out, or clip away with `selector`, then rerun.
6. **Clean up**: stop both servers and `git worktree remove "${TMPDIR:-/tmp}/ui-before"`.

Hand over `screenshots.md`, or paste it into wherever the user wants it. For a pull request, the `pr-screenshots` skill uploads it.

## Output

The output directory defaults to `$TMPDIR/ui-screenshots/<project>-<timestamp>/`, outside the repo. If the user wants it inside the repo, make sure the path is git-ignored first. Each run first deletes the files it generates (below) from that directory, so a rerun into the same `out` leaves nothing stale; other files there are kept.

- `<shot>[-<theme>][-<viewport>]-{before,after,diff}.png`. Flat, unique file names.
- `screenshots.md`: the tables, with image paths relative to the directory, so it works as a `gh --body-file` unchanged.
- `attach.txt`: the images `screenshots.md` references, one per line, for `gh --attach`.
- `manifest.json`: every shot and variant with `changedPixels`, `changedPercent`, `sizeChanged`, or `error`.

A shot whose variants all show no change is left out of `screenshots.md` and named on stderr as "No visual change", but stays in the manifest. For a shot meant to show the change, that means it targets the wrong page or element; for a control shot of an unaffected page, it is the expected result.

## Table template

`capture.mjs` emits exactly this. One section per visual change; the caption line appears only when the shot has a `caption`.

Single variant:

```markdown
### <Change name>

<Optional one-line caption.>

| Before | After | Diff |
| --- | --- | --- |
| ![Before](./<shot>-before.png) | ![After](./<shot>-after.png) | ![Diff](./<shot>-diff.png) |
```

Several variants, one row each, labelled `<Theme> · <Viewport>` (only the parts that vary):

```markdown
### <Change name>

<Optional one-line caption.>

| Variant | Before | After | Diff |
| --- | --- | --- | --- |
| Light · Desktop | ![Before](./<shot>-light-desktop-before.png) | ![After](./<shot>-light-desktop-after.png) | ![Diff](./<shot>-light-desktop-diff.png) |
| Dark · Mobile | ![Before](./<shot>-dark-mobile-before.png) | ![After](./<shot>-dark-mobile-after.png) | ![Diff](./<shot>-dark-mobile-diff.png) |
```

A variant with no change keeps its row, with `_No visual change_` in the Diff cell. Images use markdown syntax with `./` paths because that is the form `gh --attach` rewrites to uploaded URLs; GitHub scales markdown images to fit table cells.

## Spec

```json
{
  "before": "http://localhost:4001",
  "after": "http://localhost:3000",
  "out": "/tmp/ui-screenshots/my-branch",
  "themes": [
    "light",
    { "name": "dark", "colorScheme": "dark", "localStorage": { "theme": "dark" }, "attributes": { "data-theme": "dark" } }
  ],
  "viewports": ["desktop", "mobile"],
  "mask": ["[data-testid=clock]"],
  "shots": [
    { "name": "Settings cards", "caption": "Cards are rounded and stack on mobile.", "path": "/settings" },
    { "name": "Save button", "path": "/settings", "selector": "form .actions", "viewports": ["desktop"],
      "actions": [{ "hover": "button[type=submit]" }] }
  ]
}
```

Top level:

- `before`, `after` (required): base URLs. A shot's `path` is appended as-is.
- `shots` (required): list of shots, below.
- `out`: output directory.
- `themes`: the theme matrix. `"light"` and `"dark"` only emulate `prefers-color-scheme`. For a site with a manual toggle, use an object: `name`, `colorScheme`, `localStorage` (set before any page script runs), `attributes` (set on `<html>` before load and again after it, e.g. `{"class": "dark"}`), `initScript` (JS source run before page scripts). Default `["light"]`.
- `viewports`: the viewport matrix. Presets: `desktop` 1280×800, `tablet` 768×1024, `mobile` 390×844, or `{ "name", "width", "height" }`. Default `["desktop"]`.
- `deviceScaleFactor` (default 1; use 2 for fine detail), `fullPage` (default false), `mask` (selectors painted over in both images), `localStorage` and `initScript` (applied to every theme).
- `threshold` (default 10): a pixel counts as changed only when one of its RGBA channels differs by more than this, on a 0–255 scale. 10 ignores antialiasing noise on text and edges. Lower it (even to 0) when the change is a subtle colour shift that the diff misses; raise it when unaffected areas still show scattered red specks.

Per shot:

- `name` (required): the heading and file-name stem.
- `path` (default `/`), `caption`, `selector` (clip to its first match only; select a container to capture several items), `fullPage`, `mask`.
- `actions`: run in order after load, identically on before and after, each one of `{"click": sel}`, `{"hover": sel}`, `{"fill": [sel, text]}`, `{"press": "Escape"}`, `{"waitFor": sel}`, `{"wait": ms}`, `{"eval": "js"}`.
- `waitFor` (selector), `wait` (ms): before the screenshot.
- `themes`, `viewports`: names that narrow the matrix for this shot.

Every capture uses a fixed viewport, `reducedMotion: 'reduce'`, CSS that zeroes animations and transitions, a hidden caret, `networkidle`, and `document.fonts.ready`. The same CSS hides common dev overlays (`astro-dev-toolbar`, `vite-error-overlay`, `nextjs-portal`, the webpack overlay). `mask` cannot reach inside an overlay's shadow DOM; add any other overlay's host element to a shot's `actions` as `{"eval": "document.querySelector('<host>')?.remove()"}`.

## Playwright

`capture.mjs` loads `playwright` (or `@playwright/test`) from the project's `node_modules`, and otherwise installs it once into `${XDG_CACHE_HOME:-~/.cache}/ui-screenshots` with `npm install --prefix`. Neither path writes to the repo. If Chromium is missing, the script prints the exact `node .../playwright-core/cli.js install chromium` command that matches the Playwright version it loaded; run it and retry. That command is the version-matched form of `npx playwright install chromium`.

If `node` refuses to run with "No version is set" (asdf outside a project), run from the project root or set `ASDF_NODEJS_VERSION`.
