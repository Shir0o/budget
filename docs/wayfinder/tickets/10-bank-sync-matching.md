# Bank sync and transaction matching

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)
- **Depends on:** [SimpleFIN Bridge behavior](03-simplefin-behavior.md)

## Question

How does SimpleFIN bank sync connect, when does it fetch, and how are incoming bank transactions matched, de-duplicated, and updated?

## Resolution

### Connection

- **One device runs bank sync for a budget** (default: Android). The **access URL never leaves that device.** It lives in Android Keystore or the macOS Keychain and is never written to the sync log. Other devices see results through the synced events. This also prevents two devices from using up the rate limit.
- **Account linking:** each SimpleFIN account is linked to one app account, or set to ignore. We store the SimpleFIN account id, the institution name, and a display name trimmed to at most a **last-4** suffix. We never store a full number.
- **Linked-from date:** set per account. It defaults to the day after the newest imported transaction in that account. Bank transactions before it are ignored, which prevents duplicating migrated history.

### Fetch schedule

- **Automatic:** at most every 6 hours (4 per day), through Android WorkManager or while the Mac app is running.
- **Manual:** allowed. A hard cap of **20 requests per day** keeps us under the 24-per-day limit, and the UI shows how many fetches are left.
- **Window:** start = max(linked-from date, last successful fetch − 10 days, today − 90 days). Every request uses `pending=1`.
- **Errors:** messages from the `errors` array are shown as a banner. An auth failure pauses automatic fetches until you re-link.

### Matching order (per incoming bank transaction)

1. **Same SimpleFIN id already imported:** update it in place (amount, date, description, pending).
   - If the line was already **Reviewed** and the amount changed, it goes back to **Unreviewed** with the note "changed by bank: $X → $Y".
   - Only the bank's fields change. The memo, categories, business status and Review stay the person's, and a cleared line never goes back to pending.
   - On a split, the person's lines stay and the difference goes in a new **Unreviewed**, uncategorized line with that note, so the lines still sum to the amount.
   - A **Reconciled** transaction is never edited by a fetch (ticket 09: edits need a confirmation). If the bank's amount changed, its lines go back to **Unreviewed** with the note "bank shows $Y, Reconciled at $X" until the person edits it.
2. **A pending charge posted under a new id:** there is a still-pending imported transaction in the same account, posted date within 7 days of it, the same normalized description (or a payee similarity ≥ 0.8), and an amount within +25% or −10% (tips, fuel holds).
   - Replace it in place, keeping the user's category, business status, and memo.
   - If the amount changed, send it back to Review.
3. **A pending charge vanished:** a pending transaction missing from the bank feed for 10 days with no match becomes **dropped**. It is removed from balances, and history keeps it.
4. **Looks like a transaction entered by hand or from a schedule:** an unlinked transaction in the same account with the **exact amount**, dated within ±5 days. Offered as a **proposed match** for you to confirm or reject. Never merged automatically.
5. **Otherwise:** create a new **Unreviewed** transaction with actor `bank-sync`.

- **Balance check** after each fetch: compare the bank's `balance` with the app's balance (cleared + uncleared, pending included). If they differ, show a discrepancy badge on the account that links to Reconcile.
