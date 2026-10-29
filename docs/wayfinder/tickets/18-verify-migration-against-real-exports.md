# Verify migration against real exports

- **Status:** closed (2026-10-29)
- **Type:** `wayfinder:task`
- **Map:** [Budget business logic](../map.md)
- **Depends on:** [Provide real Actual and YNAB exports](05-provide-sample-exports.md)

## Question

Do the field mappings in tickets 01, 02, and 14 hold up against the user's actual files? What tags, flags, and expected differences show up in them?

## Resolution

Verified locally against `private/actual-export.zip` and `private/ynab-export.zip` without exposing any private transaction details or committing real financial data.

### 1. Schema & Format Confirmations
- **Actual Budget:**
  - `transactions.date`: integer `YYYYMMDD` (e.g. `20231231`, `20261028`). Confirmed.
  - `zero_budgets`: `month` is integer `YYYYMM`, `amount`, `carryover`, `goal`, `long_goal`. Confirmed.
  - Split structure: `isParent = 1` on parent row, `isChild = 1` and `parent_id` on child lines. Confirmed.
- **YNAB:**
  - Dates in `Register.csv`: `MM/DD/YYYY` format.
  - Splits in `Register.csv`: `Split (n/m)` prefix in `Memo` (e.g., `Split (1/3)`, `Split (2/3)`). Confirmed.
  - `Plan.csv` columns: `Month`, `Category Group/Category`, `Category Group`, `Category`, `Assigned`, `Activity`, `Available`. Confirmed.

### 2. Tag & Flag Mapping (1:1 Correspondence)
Both systems use an identical set of 6 business expense labels:
- **YNAB Flags:** `Work Assets`, `Work Expenses`, `Work Meals`, `Work Subscriptions`, `Work Supplies`, `Work Travel` (modern YNAB exports flag text labels, not just color names).
- **Actual Tags:** `#workAssets`, `#workExpenses`, `#workMeals`, `#workSubscriptions`, `#workSupplies`, `#workTravel` (embedded in transaction `notes`, 564 transactions tagged).
- **Preset Mapping:**
  - `Work Meals` / `#workMeals` → Meals (50% deductible)
  - `Work Travel` / `#workTravel` → Travel (100% deductible)
  - `Work Subscriptions` / `#workSubscriptions` → Software & subscriptions (100% deductible)
  - `Work Supplies` / `#workSupplies` → Supplies (100% deductible)
  - `Work Expenses` / `#workExpenses` → Other business expense (100% deductible)
  - `Work Assets` / `#workAssets` → Other / Equipment (100% deductible or depreciable asset)

### 3. Counts & Overlap
- **Date Range:** 35 months shared across both files (Dec 2023 – Oct 2026).
- **Transactions:** 2,995 active in Actual vs. 2,972 in YNAB. The user actively used both or migrated with near-complete overlap; Actual has ~30 additional transactions in Jul–Sep 2026.
- **Accounts:** 20 in Actual, 19 in YNAB. 18 exact name matches. 1 account has duplicated name in YNAB (`... - ...`). 1 account (`EBT`) exists only in Actual.
- **Category Groups:**
  - Shared: `Bills`, `Needs`, `Wants`.
  - YNAB only: `Credit Card Payments` (5 card payment categories automatically derived in YNAB).
  - Renamed: `Savings (hidden)` in Actual vs. `Hidden Categories` in YNAB; `Income` in Actual vs. `Inflow: Ready to Assign` in YNAB.

All assumptions in tickets 01, 02, and 14 are verified and ready for `budget_core` implementation.
