# Budget business logic (wayfinder map)

- **Label:** `wayfinder:map`
- **Tracker:** local markdown (`docs/wayfinder/tickets/`). Move to GitHub Issues on `Shir0o/budget` once the repo exists.

## Destination

A complete business-logic spec for a private, local-first, zero-based envelope budget (Android first, then macOS) that someone can build `budget_core` from with nothing left to decide. It includes the repo and stack setup. UI design and code are excluded.

## Notes

- Single user. USD. Several budgets allowed. Privacy first: works offline, no account, no telemetry, data encrypted on the device, every integration opt-in.
- Glossary: [CONTEXT.md](../../CONTEXT.md). Decisions: [docs/adr](../adr/).
- On 2026-10-29 the user delegated every remaining decision to the agent. Tickets marked "user delegated the decision" were settled by the agent using the recommendations the user had accepted in earlier rounds.
- Real export files live only in `private/` (gitignored). The repo is public.

## Decisions so far

- [Actual Budget export format](tickets/01-actual-export-format.md): zip of `db.sqlite` + `metadata.json`; amounts in integer cents, `YYYYMMDD` dates, tombstones, `#tags` in notes.
- [YNAB export format](tickets/02-ynab-export-format.md): Register.csv + Plan.csv; Outflow/Inflow, flattened `Split (n/m)` rows, `Transfer : X` payees.
- [SimpleFIN Bridge behavior](tickets/03-simplefin-behavior.md): setup token → access URL; ≤ 24 requests/day; ≤ 90-day window; pending charges can get new ids when they post.
- [Schedule C business tags and deduction rules](tickets/04-schedule-c-business-tags.md): 19 preset tags mapped to Schedule C lines; meals 50%, gifts $25 per recipient, business-use %.
- [Event log structure and merge rules](tickets/06-event-log-and-merge.md): HLC-ordered, attributed events; field-level last writer wins; assignments as deltas; delete beats a concurrent edit.
- [Budget math: rollover, overspending, credit cards](tickets/07-budget-math.md): YNAB-style rollover; cash overspending hits next month's Ready to Assign; credit overspending becomes unfunded debt.
- [Targets, automation, and predicted expenses](tickets/08-targets-and-automation.md): four target kinds; off/suggest/auto per category; priority fill; 12-month forecast; recurring-charge suggestions.
- [Transactions, Review, and Business Tags](tickets/09-transactions-review-business-tags.md): every line needs a category + Personal/Business from a person; yearly deductible report with CSV.
- [Bank sync and transaction matching](tickets/10-bank-sync-matching.md): one device holds the token; ≤ 20 fetches/day; id → pending-posted → manual-match order; changed amounts go back to Review.
- [Change History and revert](tickets/11-change-history-revert.md): revert by group with conflict prompts; restore to a date as one group; audited redaction.
- [Sync, encryption, and keys](tickets/12-sync-encryption-keys.md): per-device encrypted segments in Drive `appDataFolder`; QR pairing; 24-word recovery phrase.
- [MCP tools and redaction](tickets/13-mcp-tools-redaction.md): macOS stdio server; Off/Read-only/Read-write; no deletes; can't mark lines Reviewed; Luhn/ABA redaction.
- [Migration: Actual import, YNAB comparison, and tag mapping](tickets/14-migration-import-compare.md): import all of Actual's history as one revertable group; four-part comparison with YNAB; pull in missing items one by one.
- [Tech stack and module boundaries](tickets/15-tech-stack.md): Flutter + a pure-Dart `budget_core` workspace; SQLCipher; libsodium; notarized DMG + Play Store.
- [Open-source repo settings](tickets/16-open-source-repo-settings.md): public `Shir0o/budget`, MIT, org Tier 2 now and Tier 1 with the first code, push protection, `no-real-data` CI check.

## Open tickets (frontier)

- [Provide real Actual and YNAB exports](tickets/05-provide-sample-exports.md): **HITL, you.** Unblocks the verification below.
- [Verify migration against real exports](tickets/18-verify-migration-against-real-exports.md): blocked by the ticket above.

## Not yet specified

- Receipt photos attached to transactions (affects sync size and the encryption design).
- OFX/QFX import.
- A second sync backend (Syncthing or any folder) behind the segment interface.

## Out of scope

- [Design mock-up first or code first](tickets/17-design-vs-code-first.md): the user removed it; the map ends at the spec.
- Sharing with other people or households; iOS, Windows, web.
- Mileage log and home office (Form 8829); filing taxes or tax advice.
- Product naming and branding.
