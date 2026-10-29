# MCP tools and redaction

- **Status:** closed
- **Type:** `wayfinder:grilling`
- **Map:** [Budget business logic](../map.md)

## Question

Which MCP tools does the local server expose, what are its write limits, and how are card and account numbers kept away from AI agents?

## Resolution

### Server

- A `budget-mcp` command-line binary bundled with the **macOS app only**. It uses stdio transport and is launched by the MCP client (Claude Desktop, Antigravity, and others).
- It reads and writes the same local encrypted database. The key comes from a Keychain item shared with the app. Writes are appended as events, and the app picks them up live.
- **Settings → MCP:** `Off` (default), `Read-only`, or `Read-write`, chosen per budget. Settings shows a copy-paste client config. Every connection appears as "Last used by <client> at <time>".

### Read tools

`list_budgets`, `get_month(month)`, `list_categories`, `list_accounts`, `search_transactions(filters, page)` (≤ 200 results per page), `get_transaction`, `list_unreviewed`, `list_targets`, `get_forecast(months)`, `get_business_report(year)`, `get_change_history(filters)`.

### Write tools (Read-write mode only)

- **Transactions:** `create_transaction`, `update_transaction` (payee, date, amount, memo, cleared), `split_transaction`.
- **Assignments:** `assign(category, month, amount)`, `move_money(from, to, month, amount)`.
- **Schedules and targets:** `create_schedule`, `update_schedule`, `set_target`, `clear_target`.
- **Categories:** `create_category`, `rename_category`, `archive_category`.
- **Review pre-fill:** `suggest_review(transaction, line, category, business)` **fills in** category and business status, but the line **stays Unreviewed** until you confirm it in the app. This keeps "I check each transaction myself" true.
- **Revert:** `revert_change(groupId)`, only for groups whose actor is `mcp:*`.

### Never exposed

- Deleting budgets, accounts, or transactions. MCP can only archive budgets and accounts, and can't remove transactions at all.
- Bank-sync credentials or settings, sync and key settings, MCP settings, export or backup, redaction, and marking a line Reviewed.

### Audit

- Each tool call is one event group with `actor = mcp:<clientInfo.name>`, shown in Change History and revertable (ticket 11).

### Redaction (applies to every string the server returns, including memo, payee, account name, and notes)

1. **Card-like numbers:** a run of 12–19 digits (spaces and dashes allowed) that passes the Luhn check becomes `[card ••1234]`.
2. **Routing numbers:** 9 digits with a valid ABA checksum become `[routing]`.
3. **Other long numbers:** any other run of ≥ 8 digits becomes `[number ••1234]`.
4. **Account names:** reduced to at most a last-4 suffix.

- **Inputs:** write tools **reject** values that match rules 1–3, with the error "Account or card numbers can't be stored."
