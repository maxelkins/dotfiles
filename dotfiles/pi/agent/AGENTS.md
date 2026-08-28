# Global Instructions

- For GitHub repository, issue, pull request, workflow, release, or commit URLs, use the authenticated `gh` CLI first. Only use web-fetching tools if `gh` fails.
- Never write resolved credentials, private keys, or session data to this repository. Approved `op://...` references may be tracked, but their resolved values may not.
- `dotfiles/pi/agent/.gitignore` is a publication allowlist. Review any change that permits another Pi path instead of adding a broad directory exception.
