---
name: pr-screenshots
description: 'Add before/after/diff screenshots of UI changes to a GitHub pull request, uploaded with gh --attach. Use when opening a PR whose diff changes UI, or when asked to add screenshots to a PR.'
---

# pr-screenshots

Put one comparison table per visual change in the PR body's `## Screenshots` section. The `ui-screenshots` skill captures them; this skill decides what to shoot and uploads the result with `gh`. Images are uploaded as GitHub attachments, never committed.

## Steps

1. **Check gh can attach.** Run `gh pr create --help | grep -- --attach`. If nothing matches, stop and tell the user to upgrade `gh`.
2. **Decide whether the diff touches UI.** Read `git diff <base>...HEAD`, not just the file list. UI means a change a user could see in a rendered page: markup, templates, components, styles, theme tokens, copy, icons and images. Tests, types, refactors with identical output, and server-only code are not UI. If nothing is visible, leave the PR without a Screenshots section and stop.
3. **List the visual changes**, each with the page (and the component, if local) where a reviewer sees it, and whether it needs light+dark or desktop+mobile (see `ui-screenshots`). Done when every visible hunk in the diff maps to a shot.
4. **Capture** with the `ui-screenshots` skill, base ref = the PR's base branch. Done when the red in every diff image is confined to the changed component; content shifted inside it is expected. If a shot meant to show a change reports "No visual change", its page or selector is wrong: fix it, or drop the change if it is truly invisible. A control shot of an unaffected page reporting "No visual change" is fine.
5. **Upload** into the PR body (below), then `gh pr view <n> --json body -q .body` and check each image is now a `https://github.com/user-attachments/...` URL and no `./` path is left.

## Uploading

`gh pr create`, `gh pr edit`, and `gh pr comment` take `--attach <path>` (repeatable, at most 50 per call, optional `'<path>#<alt text>'`). When the body names an attached file as `![alt](./file.png)`, gh uploads it and rewrites the reference to its URL. Paths in a `--body-file` resolve against the body file's directory, then the current directory. gh appends any attached file the body does not reference, so attach exactly the files in `attach.txt`. On a partial upload failure, gh still prints the PR URL but exits non-zero; check the body and retry the missing images with `gh pr edit`.

Write the body file inside the screenshots output directory (`$OUT`, printed by `capture.mjs`) so the `./` paths resolve, and build the attach flags from `attach.txt`:

```sh
cd "$OUT"
attach=(); while read -r f; do attach+=(--attach "$f"); done < attach.txt
```

- **New PR** (from the `open-pr` skill): write the full body to `$OUT/body.md` with the contents of `screenshots.md` as the Screenshots section, then `gh pr create --title "<title>" --body-file body.md "${attach[@]}"`.
- **Existing PR**: save `gh pr view <n> --json body -q .body` to `$OUT/body.md`, replace the content of its `## Screenshots` section (or add the section at the end) with `screenshots.md`, then `gh pr edit <n> --body-file body.md "${attach[@]}"`. When the user asks for a comment instead, run `gh pr comment <n> --body-file screenshots.md "${attach[@]}"`.

With more than 50 images, upload them in several calls: put the first tables in the body, and post the rest with `gh pr comment`, splitting `screenshots.md` and `attach.txt` at a `###` heading.
