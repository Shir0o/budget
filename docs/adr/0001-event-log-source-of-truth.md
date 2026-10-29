# 0001 Event log as the source of truth

- **Status:** accepted (2026-10-29)

## Context

The user wants Change History with revert, offline use on two devices with sync, and a record of exactly what bank sync, automation, and MCP agents changed. A mutable "current state" database would need a separate audit table, a separate sync protocol, and conflict detection. Those three would drift apart.

## Decision

Every change is an immutable, attributed event ordered by a hybrid logical clock. Current state is a projection with snapshots. Sync exchanges event segments; merges are last-writer-wins per field, with additive assignment deltas. Revert emits compensating events. Redaction of accidentally stored sensitive values is the single, audited exception to immutability.

## Consequences

- Change History, revert, sync, and attribution all come from one mechanism.
- Storage grows forever. Snapshots handle startup time; the log itself is small (text-only, one person).
- Every new feature must be expressed as events, and the projections must be deterministic.
- Hard to reverse: migrating away later means converting the log into a state model.

## Alternatives rejected

- **State database + audit table:** the audit can drift from the state, and it does nothing for sync.
- **A full CRDT library (Automerge or Yjs):** heavier than needed for a single user; our merge rules are domain-specific (assignment deltas, delete beats a concurrent edit).
