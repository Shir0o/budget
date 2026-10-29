# Transactions, Review, and Business Tags

- **Status:** closed
- **Type:** `wayfinder:grilling`
- **Map:** [Budget business logic](../map.md)
- **ADR:** [0003 No auto-categorization](../../adr/0003-no-auto-categorization.md)
- **Depends on:** [Schedule C business tags and deduction rules](04-schedule-c-business-tags.md)

## Question

What does a transaction need before it counts as reviewed, how do Business Tags attach, and what does the business report produce?

## Resolution

### Review

- **Every line** of a transaction is either **Unreviewed** or **Reviewed**.
- A line becomes Reviewed only when a person sets both:
  1. a **category**, or Ready to Assign for income, and
  2. a **business status**: `Personal`, or `Business(<tag>)`. Gift lines also need a **recipient**.
- **Transfer lines skip business status.** A transfer is not spending.
- **Hint chip:** shows the category and business status most recently used for the same payee. Nothing is applied until you tap it, and there is no "approve all" action that applies hints.
- **Other sources of values:** bank sync, scheduled entries, and MCP may *fill in* fields, but only a person marks a line Reviewed (MCP limits are in ticket 13).
- **Unreviewed lines still count in the budget math.** An uncategorized line sits in a virtual "Uncategorized" bucket, which reduces Ready to Assign until it is categorized.

### Imported history

- **Current tax year:** imported as Unreviewed, pre-filled from the tag mapping (ticket 14).
- **Earlier years:** imported as Reviewed. Lines whose flag, `#tag`, or category maps to a Business Tag get that tag; all other lines are `Personal`.

### Other transaction rules

- **Splits:** any number of lines. Lines must sum to the parent amount, and each line has its own category, business status, and memo.
- **Cleared status:** `uncleared`, `cleared`, or `reconciled`.
- **Reconcile:** enter the bank balance; the SimpleFIN balance is offered as a default. If the cleared balance matches, cleared transactions become reconciled. Reconciled transactions need a confirmation before editing.
  - On a mismatch, you can create an **adjustment transaction** (Unreviewed, categorized to Ready to Assign).
- **Blocked content:** memo and payee fields reject anything that looks like a card or account number (the pattern from ticket 13), with the message "Don't store account numbers here."

### Business Tags

- Preset list and deduction rules: see ticket 04. Custom tags are allowed.
- **Business-use %** is set per tag per tax year. If it's missing, the report shows a ⚠ for that tag.
- **Gift cap:** each recipient's deductible gifts per tax year are capped at $25. The report applies the cap in date order.

### Business report (one tax year = one calendar year)

- **Summary:** for each tag, its Schedule C line, gross amount, rule, and **deductible amount**. Then total self-employment income, total deductible expenses, and net.
- **Detail:** every tagged line with date, payee, account, amount, memo, tag, recipient, and deductible amount.
- **Warnings:** Unreviewed lines in the year, missing business-use %, and gift lines without a recipient.
- **Export:** CSV with two files (summary and detail). The data is produced on the device and never uploaded. A footer reads: "Records only. Not tax advice."
