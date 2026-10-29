# 0003 No auto-categorization

- **Status:** accepted (2026-10-29)

## Context

Actual (rules) and YNAB (payee memory) categorize transactions automatically by default. The user needs to decide by hand, for every transaction, its category and whether it is a reportable self-employment expense. Auto-applied categories quietly skip that review and corrupt the business report.

## Decision

Nothing assigns a category or business status without a person's tap. The app may show a hint chip (last-used values for the payee). Bank sync, schedules, imports, and MCP may only *pre-fill* values; a line becomes Reviewed only after the user confirms it. Actual's rules are not imported.

## Consequences

- More taps per transaction. This is by design: review is part of the product.
- Business reports can trust that every line was looked at by a person.
- A future reader will expect a rules engine. This ADR is why there isn't one.
