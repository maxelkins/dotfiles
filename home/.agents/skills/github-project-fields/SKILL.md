---
name: github-project-fields
description: Edit GitHub Projects v2 fields on issues and pull requests with the authenticated gh CLI. Use when asked to set project Status, refinement, priority, estimate, iteration, date, or other project-board field values, including bulk updates.
---

# GitHub project fields

Use `gh project item-edit` for Projects v2 fields. `gh issue edit` changes issue properties, not project fields.

## Workflow

1. Identify the issue or pull request URLs, project owner, and project number. Inspect memberships when the project is not explicit:

   ```bash
   gh issue view ISSUE --repo OWNER/REPO --json url,projectItems
   gh project list --owner OWNER --format json
   ```

   Match the intended project exactly. Ask the user if more than one project is plausible.

2. Confirm every requested field and value exists before writing:

   ```bash
   gh project field-list PROJECT_NUMBER --owner PROJECT_OWNER --format json
   ```

   Preserve the option's exact spelling, capitalisation, and emoji. If authentication lacks Projects access, report the failure and suggest `gh auth refresh -s project`.

3. Update one field per invocation. Prefer names over opaque GraphQL IDs:

   ```bash
   gh project item-edit PROJECT_NUMBER \
     --owner PROJECT_OWNER \
     --url ISSUE_OR_PULL_REQUEST_URL \
     --field "FIELD_NAME" \
     --value "OPTION_NAME"
   ```

   For a batch, use `set -euo pipefail`, quote every value, and loop over exact URLs:

   ```bash
   set -euo pipefail
   urls=(
     "https://github.com/OWNER/REPO/issues/123"
     "https://github.com/OWNER/REPO/issues/124"
   )

   for url in "${urls[@]}"; do
     gh project item-edit PROJECT_NUMBER --owner PROJECT_OWNER \
       --url "$url" --field "Status" --value "To do"
     gh project item-edit PROJECT_NUMBER --owner PROJECT_OWNER \
       --url "$url" --field "Refinement status" --value "Ready to refine"
   done
   ```

4. Verify every target after writing:

   ```bash
   gh project item-list PROJECT_NUMBER \
     --owner PROJECT_OWNER \
     --format json \
     --limit 10000
   ```

   Filter `.items[]` by the exact `.content.url` and inspect the requested fields. The task is complete only when every target has every requested value.

## Constraints

- Treat the issue number, issue GraphQL ID, project number, project GraphQL ID, and project-item ID as different identifiers.
- Select the project through `PROJECT_NUMBER` and `--owner`; `--url` is the issue or pull request URL.
- An issue can belong to several projects. Update only the project the user named or confirmed.
- If the item is absent from that project, report it. Add it with `gh project item-add` only when the user also asked to add project membership.
- For non-draft issues and pull requests, run one `item-edit` command per field.
- Query field options at execution time. Do not cache project, field, item, or option IDs in the skill.
- Report the project, fields, values, and verified item count after the update.

## ID-based fallback

If the installed `gh` version lacks `--url`, `--field`, or `--value`, query the project, field option, and project-item GraphQL node IDs. Then use:

```bash
gh project item-edit \
  --id PROJECT_ITEM_ID \
  --project-id PROJECT_ID \
  --field-id FIELD_ID \
  --single-select-option-id OPTION_ID
```

Verify through GraphQL or `gh project item-list` using field names and values, rather than treating a successful command exit as sufficient.
