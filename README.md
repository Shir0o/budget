# Budget

A private, local-first, zero-based envelope budget. Android first, macOS second.

> **Status:** early development. You can create a budget, add an account and record income.

## Privacy promises

- **Works offline, no account.** Your budget lives on your device, in an encrypted database.
- **Zero telemetry.** The app sends nothing to us. There is no "us" server.
- **Everything else is opt-in and off by default:**
  - **Bank sync** through [SimpleFIN Bridge](https://beta-bridge.simplefin.org/). Read-only, and the token stays on one device.
  - **Device sync** through your own Google Drive. It's end-to-end encrypted, so Google sees only scrambled files.
  - **MCP server** on macOS. AI agents can read your budget, and with read-write turned on they can edit it. Card and account numbers are redacted, and every change can be reverted.
- **No lock-in.** Export to CSV or JSON at any time.

## What it does

- Zero-based budgeting (give every dollar a job), with rollover and YNAB-style credit card handling
- Targets and automation: repeating amounts, one-time amounts by a date, keep-at-least, and schedule-driven targets, plus a 12-month forecast of predicted expenses
- Manual review of every transaction (nothing is categorized automatically), with Schedule C-aligned business tags and a yearly deductible report
- Full change history with revert
- A one-time migration from Actual Budget, with a check against your old YNAB export

## Docs

- [CONTEXT.md](CONTEXT.md): glossary
- [docs/wayfinder/map.md](docs/wayfinder/map.md): every decision and its ticket
- [docs/adr](docs/adr): architecture decision records
- [PRIVACY.md](PRIVACY.md): privacy policy

## License

[MIT](LICENSE)
