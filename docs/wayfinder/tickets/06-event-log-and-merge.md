# Event log structure and merge rules

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)
- **ADR:** [0001 Event log as the source of truth](../../adr/0001-event-log-source-of-truth.md)

## Question

How is budget data stored so that Change History, revert, and two-device sync all fall out of a single model? And how are concurrent edits merged?

## Resolution

**Event** fields:

| Field | Meaning |
|---|---|
| `id` | UUIDv7 |
| `budgetId` | Budget it belongs to |
| `deviceId` | Random id created once per install |
| `hlc` | Hybrid logical clock (wall ms + counter + deviceId). Gives a total order across devices |
| `actor` | `user@android`, `user@mac`, `bank-sync`, `automation`, `import`, `mcp:<client name>`, `revert` |
| `groupId` | Groups events from one user action, automation run, import, or MCP tool call. Revert works per group |
| `type` + `payload` | Domain change (below) |

**Event types (v1):**
- Lifecycle of budget, account, category group, category, payee, and Business Tag: `Created`, `FieldsSet{field: value}`, `Archived`, `Unarchived`, `Deleted`.
- `TransactionCreated`, `TransactionFieldsSet`, `TransactionSplitSet{lines}`, `TransactionDeleted`.
- `AssignmentChanged{category, month, deltaCents}`, `ScheduleCreated/FieldsSet/Deleted`, `TargetSet/Cleared`.
- `ReviewSet{transaction, line, category, business: personal|tag}`.
- `Reconciled{account, date, clearedBalance}`.
- `Redacted{entity, field, eventIds}` (see ticket 11).

**State** is a projection: replay the events in `hlc` order. Snapshots (checkpoints) every 1,000 events keep startup fast. Events are never deleted; `Redacted` is the only exception (ticket 11).

**Merge rules** (when both devices edited offline):
1. **Field-level last writer wins.** For each `(entity, field)`, the event with the highest `hlc` wins. The losing value stays visible in Change History, labelled "overwritten by sync".
2. **Assignments are deltas**, so concurrent assignments add up instead of one overwriting the other. Example: phone +$50 and Mac +$30 to Groceries in November give +$80.
3. **Delete beats a concurrent edit.** An edit to a deleted entity is kept in history, and the entity can be restored by reverting the delete.
4. **Split lines are replaced as a whole** (`TransactionSplitSet` is last writer wins on the whole line set), so lines from two devices are never mixed.
5. **Invariant checks** run after every merge: transfer pairs both exist, split lines sum to the parent amount, and Card Payment categories exist for each card. Anything that fails is recorded as a `needs-attention` item in the review queue and never fixed silently.
