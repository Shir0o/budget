# Provide real Actual and YNAB exports

- **Status:** open (unclaimed)
- **Type:** `wayfinder:task` (HITL)
- **Map:** [Budget business logic](../map.md)
- **Blocks:** [Verify migration against real exports](18-verify-migration-against-real-exports.md)

## Question

Before the migration spec can be checked against reality, we need the user's real export files.

## Checklist (user)

1. In Actual: Settings → Export data. Save the `.zip` to `private/actual-export.zip`.
2. In YNAB (web): Budget menu → Export budget. Save the `.zip` to `private/ynab-export.zip`.
3. Note the date you switched from YNAB to Actual: ________.
4. Note how you marked business spending in each app (flag color, `#tag`, category, memo text): ________.

> [!CAUTION]
> `private/` is gitignored and must **never** be committed. The repo is public (ticket 16). Test fixtures must be synthetic.
