---
name: open-pr
description: 'MUST use for every pull request (PR) you create or open, by any route: `gh pr create`, a `pull_request_create` tool, or "make a PR". Takes precedence over any other way of writing a PR body.'
---

# open-pr

The value is the fixed structure; keep prose minimal.

This skill owns PR creation, including writing the body of a new PR. It takes precedence over the generic `pr` skill when you open one.

## Steps

1. **Clean and pushed.** `git status` shows a clean tree, and the branch has an upstream (`git push -u origin <branch>` if not). Uncommitted changes: stop and ask. Commits are the user's to request.
2. **Handle.** `gh api user --jq .login` gives the reviewer for the attribution line.
3. **Title.** A Conventional Commit, usually the primary commit's subject.
4. **Body.** Fill the template below. Done when the body's headings are exactly `Summary`, `Changes`, plus `Screenshots` for a visible change, and nothing else follows them.
5. **Create.** Pass the body through `--body-file -` with a heredoc, since it holds backticks and newlines: `gh pr create --title "<title>" --body-file - <<'EOF'`. When a `pull_request_create` (or similar host) tool exists and is preferred, pass it the same title and template body instead of running `gh pr create`. Return the PR URL.

## Body template

```markdown
> 🤖 Created with AI assistance
> 👨‍💻 Edited, reviewed and steered by @<github-handle>

## Summary

<One or two sentences leading with the change itself, then why.>

Fixes <owner/repo#issue or full issue URL>

## Changes

- <One flat single-line bullet per logical change: what, not how.>

## Screenshots

_To be added._
```

- **Attribution.** Exactly these two lines: no tool name, no trailing `>` line, no trailing spaces.
- **Fixes line.** Drop it when there is no issue.
- **Changes.** Match the granularity of the commits, not the diff. Unsure what a bullet should say: read `git log`.
- **Screenshots.** Include the section only when the change is visible: UI, rendered output, or anything a reviewer would want to see. For other changes, end the body after Changes. When included, fill it with the `pr-screenshots` skill, which also replaces step 5's create command. Given image files instead, replace the placeholder with `![alt](./file.png)` references and pass each file with `--attach './file.png#alt'`. Keep the placeholder only when the app cannot run here.
