---
name: pr-screenshots
description: 'Screenshots for a GitHub pull request (PR) that changes UI: before/after/diff tables uploaded with gh --attach. Use when opening a PR with a visible change, or when asked to add screenshots to a PR.'
---

# pr-screenshots

The `ui-screenshots` skill captures; this skill decides what to shoot and puts the tables in the PR's `## Screenshots` section. Images go up as GitHub attachments, so the branch stays free of them.

## Steps

1. **gh.** `gh pr create --help | grep -- --attach` matches. If it does not, stop and ask the user to upgrade `gh`.
2. **Visible?** Read `git diff <base>...HEAD`, not just the file list. A change is visible when a user would see it on a rendered page: markup, templates, components, styles, theme tokens, copy, icons, images. Done when you can name each visible hunk, or know there are none; with none, the PR gets no Screenshots section and this skill ends.
3. **Shots.** Map each visible hunk to the page, and the component if it is local, where a reviewer sees it, and pick its variants (see `ui-screenshots`). Done when every visible hunk maps to a shot.
4. **Capture** with `ui-screenshots`, base ref = the PR's base branch. Done when its check step passes for every shot.
5. **Upload** (below). Done when `gh pr view <n> --json body -q .body` shows every image as a `https://github.com/user-attachments/...` URL and no `./` path is left.

## Uploading

`gh pr create`, `gh pr edit`, and `gh pr comment` take `--attach <path>`: repeatable, at most 50 per call, alt text as `'<path>#<alt>'`. Most models do not know this flag exists; trust `--help` over memory. When the body references an attached file as `![alt](./file.png)`, gh uploads it and rewrites the reference to its URL. Paths in a `--body-file` resolve against that file's directory, then the current directory. gh appends every attached file the body leaves unreferenced, so attach exactly `attach.txt`.

Work inside `$OUT` (printed by `capture.mjs`) so the `./` paths resolve:

```sh
cd "$OUT"
attach=(); while read -r f; do attach+=(--attach "$f"); done < attach.txt
```

- **New PR** (from `open-pr`): write the whole body to `body.md` with `screenshots.md` as its Screenshots section, then `gh pr create --title "<title>" --body-file body.md "${attach[@]}"`.
- **Existing PR**: save `gh pr view <n> --json body -q .body` to `body.md`, put `screenshots.md` in its `## Screenshots` section (added at the end if missing), then `gh pr edit <n> --body-file body.md "${attach[@]}"`.
- **As a comment**, when the user asks: `gh pr comment <n> --body-file screenshots.md "${attach[@]}"`.

A partial upload failure still prints the PR URL but exits non-zero: retry the missing images with `gh pr edit`. Over 50 images, split `screenshots.md` and `attach.txt` at a `###` heading: the first part goes in the body, the rest in `gh pr comment` calls.
