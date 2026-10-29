# Actual Budget export format

- **Status:** closed
- **Type:** `wayfinder:research`
- **Map:** [Budget business logic](../map.md)

## Question

What is in an Actual Budget export, and which tables and fields do we need to import its full history?

## Resolution

Source: actualbudget.org docs (Export / database schema). Confirm every field against the real file in [Verify migration against real exports](18-verify-migration-against-real-exports.md).

- **Export:** a `.zip` containing `db.sqlite` and `metadata.json` (budget name and id).
- **Money:** `INTEGER` cents. `-4500` means −$45.00.
- **Dates:** in the raw `transactions` table, an integer `YYYYMMDD` (some views expose ISO `YYYY-MM-DD`). The parser accepts both.
- **Soft delete:** each row has `tombstone`. Rows with `tombstone = 1` are ignored.

| Table | Fields we use | Maps to |
|---|---|---|
| `accounts` | id, name, `offbudget`, `closed` | Account (off-budget becomes a tracking account; closed becomes archived) |
| `category_groups` | id, name, `is_income`, hidden | Category group |
| `categories` | id, name, `cat_group`, `is_income`, hidden | Category (income categories map to Ready to Assign; see ticket 14) |
| `payees` | id, name, `transfer_acct` | Payee (a payee with `transfer_acct` marks a transfer) |
| `category_mapping`, `payee_mapping` | id → canonical id | Resolve merged categories and payees before import |
| `transactions` | id, `acct`, `category`, `amount`, `description` (payee id), `notes`, `date`, `cleared`, `reconciled`, `isParent`, `isChild`, `parent_id`, `transferred_id`, `starting_balance_flag`, `imported_description`, `financial_id`, `schedule` | Transaction, split, transfer |
| `zero_budgets` | `month` (YYYYMM), `category`, `amount`, `carryover`, `goal` | Assignment per month |
| `reflect_budgets` | the same | Present only in tracking-budget mode; we warn and import transactions only |
| `schedules` (+ `rules` for schedule conditions) | name, next date, amount, account, payee | Scheduled transaction (best effort) |
| `rules` | — | **Not imported.** No auto-categorization ([ADR 0003](../../adr/0003-no-auto-categorization.md)); they are listed in the import report |
| `notes` | id → text | Category notes. Lines with `#template` are offered as targets (best effort) |

- **Tags:** Actual's `#tag` tokens live inside transaction `notes`. Newer versions also keep a `tags` table. The parser pulls `#\w[\w-]*` tokens out of notes for tag mapping.
