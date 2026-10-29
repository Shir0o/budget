# Budget

A private, local-first, zero-based envelope budget for one person, used mainly on Android and also on macOS.

## Language

### Budgeting

**Budget**:
A self-contained set of accounts, categories, and history. A user may keep several. Always USD.

**Category**:
A named envelope that holds assigned money. Its balance rolls over from month to month.
_Avoid_: Envelope (in code/docs), bucket, jar

**Ready to Assign**:
The single pool of money that has arrived but has not yet been given to a category. Zero-based means this is driven to zero.
_Avoid_: To be budgeted, unassigned, available

**Assignment**:
Money moved from Ready to Assign into a category for a specific month.
_Avoid_: Budgeted amount, allocation

**Overspending**:
A category whose balance goes negative from cash-account spending. It is taken out of the next month's Ready to Assign.

**Card Payment Category**:
A category tied to one credit card account. When you spend on the card, that amount moves from the spending category into this category so the debt stays funded.
_Avoid_: CC payment envelope

### Accounts and transactions

**Account**:
A place money lives, such as checking, savings, or a credit card. Full bank account and card numbers are never stored.

**Transaction**:
A dated money movement in one account, assigned to a category (or to Ready to Assign, for income).

**Scheduled Transaction**:
A future or repeating transaction that has not happened yet. It is the source of predicted expenses.
_Avoid_: Recurring transaction, bill

**Review**:
The required manual step in which the user personally sets a transaction's category and its business-or-personal status. Nothing gets categorized automatically.
_Avoid_: Auto-categorize, rules

**Business Tag**:
A label marking a transaction (or one line of a split) as a reportable self-employment expense, such as Meals, Gifts, Conference, Supplies, or Work Subscription. It is independent of the category.
_Avoid_: Flag, label

### Automation

**Target**:
The amount a category should reach. Its kinds are Repeating (X every interval), One-time by date, Keep at least, or Driven by schedule.
_Avoid_: Goal (UI may say "goal"; the domain says Target)

**Automation Mode**:
A per-category setting (off, suggest, or auto) that says whether automation leaves the category alone, proposes Assignments, or makes them.

**Suggestion Batch**:
A set of proposed Assignments from one automation run, accepted all at once or line by line.

**Forecast**:
Scheduled transactions expanded into the future to show predicted expenses and balances.
_Avoid_: Projection, prediction

**Credit Overspending**:
Card spending beyond a category's Available. It becomes unfunded card debt rather than reducing Ready to Assign.

**Tracking Account**:
An account counted in net worth but outside the budget, such as a 401k or mortgage.
_Avoid_: Off-budget account

### Integrations and history

**Event**:
One immutable, attributed change to a budget. The budget's state is the replay of its Events.

**Actor**:
Who or what made an Event: the user on a device, bank sync, automation, import, an MCP client, or a revert.

**Budget Key**:
The per-budget secret that encrypts everything synced. It moves between devices only by QR code or recovery phrase.

**Redaction**:
The one permitted rewrite of history: replacing an accidentally stored sensitive value everywhere it appears.

**SimpleFIN Bridge**:
The paid, read-only US bank-data service used for bank sync. Its access token stays only on the user's devices.
_Avoid_: Simple fn, Plaid

**Change History**:
The permanent record of every change to a budget, showing who or what made it (user, bank sync, automation, MCP). Any entry can be reverted.
_Avoid_: Audit log, edit trail, undo stack

**MCP Server**:
An optional local server, on macOS only, that lets AI agents read and write the budget. Every change it makes goes into Change History.
