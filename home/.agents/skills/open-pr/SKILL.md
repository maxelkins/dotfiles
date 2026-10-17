---
name: open-pr
description: 'Create a GitHub pull request with a simple, consistent body: attribution header, one-line summary, plain-bullet changes, and a screenshots section. Use when the user asks to open/create a PR or a pull request, especially when they want a "simple" summary.'
---

# open-pr

Open a pull request whose body follows a fixed, deliberately simple structure. Keep prose minimal. The value is in the structure, not verbosity.

## Steps

1. **Confirm the work is committed and pushed.** Run `git status`. The tree should be clean. Push the current branch with `git push -u origin <branch>` if it has no upstream. Never commit or push without the user having asked. If there are uncommitted changes, stop and ask.
2. **Get the reviewer's GitHub handle** for the attribution line with `gh api user --jq .login`.
3. **Write the title** as a Conventional Commit (`fix:`, `feat:`, `chore(deps):`, etc.), usually the primary commit's subject.
4. **Fill the body template** below. Before creation, confirm its headings are exactly `Summary`, `Changes`, and `Screenshots`.
5. **Create the PR** with `gh pr create --title "<title>" --body "<body>"`, then return the PR URL.

## Body template

Fill each placeholder. Omit a section only if it genuinely doesn't apply.

```markdown
> 🤖 Created with AI assistance
> 👨‍💻 Edited, reviewed and steered by @<github-handle>

## Summary

<One or two sentences: what changed and why. No preamble.>

Fixes <owner/repo#issue or full issue URL>

## Changes

- <One plain bullet per logical change: what, not how.>
- <Keep each to a single line; no nested sub-bullets.>

## Screenshots

_To be added._
```

## Rules

- **Attribution header first.** Use a two-line blockquote: the AI-assistance line, then the human. Use no tool name, trailing empty `>` line, or trailing spaces.
- **Summary.** Lead with the change itself and skip "This PR...". Put the issue link on its own line right after it (`Fixes ...`). Drop the line if there's no issue.
- **Changes.** Use short, flat bullets, one per logical change. Match the granularity of the commits, not the diff.
- **Screenshots.** Leave the section with the `_To be added._` placeholder unless the user provides images. They usually add them by hand.
- **Fixed scope.** The PR body contains only the attribution block, Summary, optional issue link, Changes, and Screenshots. It ends after the screenshots content.
- Don't invent detail the diff doesn't support. When unsure what a bullet should say, read the commits (`git log`), not just the file list.
