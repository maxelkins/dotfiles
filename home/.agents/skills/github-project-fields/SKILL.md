---
name: github-project-fields
description: GitHub Projects v2 fields on issues and pull requests, edited with gh. Use when setting field values (Status, refinement, priority, estimate, iteration, date), singly or in bulk.
---

# GitHub project fields

`gh issue edit` cannot touch project fields; `gh project item-edit` does.

1. Resolve the project owner and number, plus the target URLs. When the project is not explicit, list candidates and ask the user if more than one fits:

   ```bash
   gh issue view ISSUE --repo OWNER/REPO --json url,projectItems
   gh project list --owner OWNER --format json
   ```

   An issue can sit in several projects; edit only the one the user named or confirmed.

2. Check that every requested field and value exists, and copy each option's spelling, capitalisation, and emoji exactly. `field-list` returns 30 fields by default, so pass `--limit` on large projects. A missing `project` token scope surfaces here: report it and suggest `gh auth refresh -s project`.

   ```bash
   gh project field-list PROJECT_NUMBER --owner PROJECT_OWNER --format json
   ```

3. Write one field per `item-edit` call (GitHub allows one per call on issues and pull requests). `--url` is the issue or pull request URL; `--owner` selects the project.

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

   `--value` takes a single-select option name. Other field types use `--date YYYY-MM-DD`, `--number`, `--text`, or `--iteration-id`; `--clear` empties a value.

   An item missing from the project is reported to the user. Run `gh project item-add` only when they also asked for membership.

4. Read every target back:

   ```bash
   gh project item-list PROJECT_NUMBER --owner PROJECT_OWNER --format json --limit 10000
   ```

   Filter `.items[]` by exact `.content.url`. Done when every target shows every requested value; then report the project, fields, values, and verified item count.

## ID-based fallback

When the installed `gh` lacks `--url`, `--field`, or `--value`, query the project, field, option, and item GraphQL node IDs, then:

```bash
gh project item-edit \
  --id PROJECT_ITEM_ID \
  --project-id PROJECT_ID \
  --field-id FIELD_ID \
  --single-select-option-id OPTION_ID
```
