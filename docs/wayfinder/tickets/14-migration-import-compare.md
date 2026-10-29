# Migration: Actual import, YNAB comparison, and tag mapping

- **Status:** closed. The rules are final; the field details get confirmed in [Verify migration against real exports](18-verify-migration-against-real-exports.md).
- **Type:** `wayfinder:grilling`
- **Map:** [Budget business logic](../map.md)
- **Depends on:** [Actual export format](01-actual-export-format.md), [YNAB export format](02-ynab-export-format.md), [Transactions, Review, and Business Tags](09-transactions-review-business-tags.md)

## Question

How does the one-time migration import the full Actual history, compare it against the YNAB export, map the old tags to Business Tags, and let the user pull in anything missing?

## Resolution

### Wizard (one time per budget, resumable until committed)

1. **Load Actual `.zip`.** Parse it and show counts: accounts, categories, transactions, months, schedules, and rules not imported.
2. **Load YNAB `.zip`** (optional). Parse it.
3. **Match names.** Pair accounts, category groups, and categories across the two files: exact names first, then proposed fuzzy matches the user confirms. Unpaired entries are listed for check (d).
4. **Map tags.** List every distinct YNAB **flag color**, Actual **`#tag`**, and **category** that was used, with counts. The user maps each one to a Business Tag or to nothing. If one line maps to two different tags, it goes to Review.
5. **Comparison report** (below). Resolve items one at a time.
6. **Commit.** Everything is written as **one `import` event group**, which can be reverted as a unit. Afterwards, bank-sync linked-from dates default to the day after the last imported transaction (ticket 10).

### Mapping Actual into our model

- **Accounts:** off-budget accounts become tracking accounts; closed accounts become archived.
- **Card Payment Categories:** created for each card account. Their balances are **derived** by replaying history under ticket 07's rules (Actual has no card payment categories).
  - If the user has a hand-made "CC payment" style category, the mapping step asks: "merge into Visa Payment, or keep as a normal category".
- **Income categories:** income lines go to Ready to Assign. The original income category name is kept as read-only `importedCategory` metadata on the transaction.
- **Assignments:** each `zero_budgets.amount` becomes an `AssignmentChanged` (one delta per category per month).
  - Actual's per-category `carryover` flag ("roll over overspending") has no equivalent here; affected months are listed in the report as expected differences.
- **Splits and transfers:** parent/child rows become splits; `transferred_id` pairs become transfers; `starting_balance_flag` rows become Starting Balance.
- **Cleared status:** cleared and reconciled carry over unchanged.
- **Notes:** become the memo. `#tags` are left in the memo, with their mapped Business Tag applied.
- **Schedules:** become scheduled transactions. Any that can't be converted are listed for manual setup.
- **Goal templates:** `#template` lines become Targets where they parse; otherwise they're listed.
- **Rules:** not imported (ADR 0003). They're listed for reference only.
- **Review state:** follows ticket 09 (current tax year Unreviewed and pre-filled; earlier years Reviewed).
- **Invariant check (blocks commit):** every imported account balance must equal Actual's balance for that account, to the cent. A mismatch is a parser bug, never a user problem.

### Comparison report (YNAB vs. imported Actual, over YNAB's full date range)

| Check | Rule | Output |
|---|---|---|
| **(a) Month-end balances** | For each paired account and month: YNAB running balance vs. imported balance | Months where they differ, with the size of the difference and the first month it appears |
| **(b) Transactions** | Key = (account, date, signed amount). Exact matches first, then ±3 days if unique. Splits compare at the parent total, then per line | Matched · matched with differences (payee, category, memo, cleared) · **YNAB only** · **Actual only** |
| **(c) Category months** | For each paired category and month: Assigned, Activity, Available | Differing cells. Expected differences (Actual carryover, card payment derivation) are labelled so they don't read as errors |
| **(d) Entities** | Accounts, groups, categories, and payees in only one file | List |

- **Resolving YNAB-only items:**
  - A YNAB-only transaction offers **Add to budget** (it's added Unreviewed) or **Ignore** (with a reason).
  - A YNAB-only category month offers **Use YNAB assignment** or **Ignore**.
  - Every decision is recorded and included in the commit group.
- **Export:** the report can be saved as CSV, and as a summary that shows what remains unresolved.
