# YNAB export format

- **Status:** closed
- **Type:** `wayfinder:research`
- **Map:** [Budget business logic](../map.md)

## Question

What is in a YNAB "Export budget" file, and how do we parse it well enough to compare it against an Actual import?

## Resolution

Source: YNAB help ("Export budget data"). Confirm against the real file in [Verify migration against real exports](18-verify-migration-against-real-exports.md).

- **Export:** a `.zip` containing `<Budget> as of <date> - Register.csv` (transactions) and `<Budget> as of <date> - Plan.csv` (older exports call it `Budget.csv`).
- **Register.csv columns:** `Account, Flag, Date, Payee, Category Group/Category, Category Group, Category, Memo, Outflow, Inflow, Cleared`.
  - `Outflow` and `Inflow` are both positive numbers. Signed amount = `Inflow − Outflow`.
  - Amounts can include a currency symbol and thousands separators. Strip them, then parse to integer cents.
  - `Date` follows the user's YNAB date setting. Detect the format by sampling rows; the order is ambiguous only when every sampled day is ≤ 12, and then we ask the user.
  - `Flag` is either a color name (Red, Orange, Yellow, Green, Blue, Purple), a custom flag label name (e.g., `Work Meals`, `Work Travel`), or blank.
  - `Cleared` is `Cleared`, `Uncleared`, or `Reconciled`.
  - **Splits** are flattened into one row per line, with a memo prefix `Split (n/m)`. Group consecutive rows that share account, date, and payee and run n = 1..m.
  - **Transfers** use the payee `Transfer : <Account name>`.
  - **Income** uses the category `Inflow: Ready to Assign` (older exports: `To be Budgeted`).
  - **Starting balances** use the payee `Starting Balance`.
- **Plan.csv columns:** `Month` (`Jan 2024`), `Category Group/Category`, `Category Group`, `Category`, `Assigned` (older: `Budgeted`), `Activity`, `Available`.
