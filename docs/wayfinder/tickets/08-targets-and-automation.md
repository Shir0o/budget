# Targets, automation, and predicted expenses

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)

## Question

How does each Target compute what a category needs, when and how does automation assign money, and where do predicted expenses come from?

## Resolution

### Targets (at most one per category)

| Kind | Inputs | Needed this month (m) |
|---|---|---|
| **Repeating** | amount A, every N days/weeks/months/years, next due date D | Monthly or longer interval: (A − Available-before-assigning) ÷ months from m to D's month, inclusive. Floor at 0, and round up to the cent on the last month so the target lands exactly. Weekly or daily: A × the number of due dates in m. |
| **One-time by date** | amount A, date D | (A − Available-before-assigning) ÷ months left including m. After D: complete. If spending then drops Available below A, the target stays complete and does not refill. |
| **Keep at least** | amount A | max(0, A − Available-before-assigning) |
| **Driven by schedule** | none; uses the category's scheduled transactions | The sum, over each scheduled outflow in the category, of its implied Repeating target (its amount, recurrence, and next date). The category's Carry counts once across them: it goes to the monthly-or-longer schedule due last first, up to its amount, then to the next. Weekly or daily schedules ignore it. |

- **Available-before-assigning** follows YNAB and depends on the kind:
  - **Repeating, Keep at least, and Driven by schedule** are for spending (YNAB's "Needed for spending" and "Refill up to"): Carry(c, m) alone. This month's Activity doesn't count, so paying the bill doesn't make the category look underfunded again. Example: Groceries $500 monthly, nothing carried, $500 assigned, $300 spent: Underfunded $0.
  - **One-time by date** is a balance to reach (YNAB's "Have a balance of X by date"): Carry(c, m) + Activity(c, m).
- **Underfunded(c, m)** = max(0, Needed − Assigned(c, m)).

**Example.** Car insurance: $600 every 6 months, next due in April. In November the category has $0. Needed = 600 ÷ 6 (Nov–Apr) = **$100/month**. In February, if the category holds $250, Needed = 350 ÷ 3 = **$116.67** (April rounds up so the total lands at $600).

### Automation runs

- **Mode, set per category:** `off`, `suggest` (default), or `auto`. Card Payment Categories default to `off`.
- **Priority:** a user-ordered list of categories. Ties go by category order on screen.
- **Triggers:** the first time the app runs on or after the 1st of a month, and whenever an income transaction is reviewed. You can also start a run by hand.
- **Algorithm:** go through categories in priority order. Give each one min(Underfunded, remaining Ready to Assign). Stop when Ready to Assign reaches 0. Never take Ready to Assign negative, never assign to future months automatically, and never take money out of a category.
- **Results:**
  - `auto` categories get `AssignmentChanged` events in **one group** with actor `automation`, revertable as a unit.
  - `suggest` categories produce one **Suggestion batch** you can accept with one tap, either all at once or line by line. An accepted batch is recorded with actor `user@<device>` and the note "accepted automation suggestion".

### Predicted expenses

- **Forecast:** expand every scheduled transaction 12 months ahead. Show:
  - each month's predicted outflow by category
  - predicted account balances (using scheduled income)
  - months where targets will be underfunded given scheduled income
- **Recurring detection (suggestions only):** 3 or more transactions with the same payee, amounts within ±10%, at a regular interval (weekly, every 2 weeks, monthly, quarterly, or yearly, ±3 days). Shown as "Make this a scheduled transaction?". Never applied automatically, and it runs entirely on the device.
- **Scheduled transactions:** when one comes due, it is entered as an **Unreviewed** transaction on its date. Bank sync matching (ticket 10) can then link it to the real bank transaction.
