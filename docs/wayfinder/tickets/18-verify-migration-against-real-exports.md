# Verify migration against real exports

- **Status:** open (blocked)
- **Type:** `wayfinder:task` (AFK once unblocked)
- **Map:** [Budget business logic](../map.md)
- **Blocked by:** [Provide real Actual and YNAB exports](05-provide-sample-exports.md)

## Question

Do the field mappings in tickets 01, 02, and 14 hold up against the user's actual files? What tags, flags, and expected differences show up in them?

## Plan

1. Read `private/actual-export.zip` and `private/ynab-export.zip` locally. Never commit them or paste their contents into tickets.
2. Confirm or correct:
   - the Actual table and column names and the date encoding
   - the YNAB date format, split memo prefix, and Plan.csv header names
3. Record **counts only**: distinct flags, `#tags`, and categories, which feed step 4 of the wizard.
4. Record the expected differences (Actual carryover months, card payment derivation, accounts paired by name).
5. Update tickets 01, 02, and 14 with any corrections, and add a short resolution here.
