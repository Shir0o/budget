# Project-Specific Rules

<!-- Repo-specific agent instructions. The rollout script never touches this file. -->

## Context

- Private, local-first, zero-based envelope budget. Flutter (Android first, then macOS). Single user, USD.
- **Status:** spec only. Read [docs/wayfinder/map.md](docs/wayfinder/map.md) before any work. Every decision lives in exactly one ticket under `docs/wayfinder/tickets/`.
- Glossary: [CONTEXT.md](CONTEXT.md). Use its terms (Category, not "envelope"; Ready to Assign; Target; Business Tag; Review).
- Decision records: [docs/adr/](docs/adr/).

## Hard rules

- **Public repo: never commit real financial data.** Real exports live only in `private/` (gitignored). Test fixtures must be synthetic. Never paste real transaction contents into issues, tickets, or PRs.
- **No auto-categorization** ([ADR 0003](docs/adr/0003-no-auto-categorization.md)). Only a person's tap marks a line Reviewed.
- **Money is `int` cents.** Never use floating point.
- **Every state change is an Event** ([ADR 0001](docs/adr/0001-event-log-source-of-truth.md)).
- `packages/budget_core` stays pure Dart with no Flutter imports.

## Planned layout

See [Tech stack and module boundaries](docs/wayfinder/tickets/15-tech-stack.md).

## Tier

Registered as Tier 2 until `budget_core` exists. Promote to Tier 1 (CI + required checks) in the PR that adds the first Dart code.
