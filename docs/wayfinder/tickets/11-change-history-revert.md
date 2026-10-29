# Change History and revert

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)
- **Depends on:** [Event log structure and merge rules](06-event-log-and-merge.md)

## Question

What can the user see in Change History, how do single-change and point-in-time reverts work, and what happens when later changes depend on the one being reverted?

## Resolution

- **What history shows:** every event group, newest first: actor, device, time, a plain-language summary ("MCP (Claude Desktop) set category of *Starbucks $6.40* to Dining"), and before/after values.
  - Filters: entity, actor, date range, and type.
  - Every transaction, category, and account has its own history tab.
- **Revert a group:** emits *compensating* events (`actor = revert`, `groupId` new, with a link to the reverted group). Nothing is erased. Reverting a revert is a redo.
- **Conflicts:** before applying a revert, the engine finds every later event that:
  1. **set the same field again.** The prompt reads: "Field changed again later by X. Revert anyway (restore old value) or skip this field?"
  2. **depends on an entity the group created** (for example, transactions in a category you're un-creating). The prompt lists those events, with the options "Revert these too" and "Cancel".

  If nothing conflicts, the revert applies right away.
- **Go back to a date:**
  - **View as of T** is read-only time travel.
  - **Restore to T** emits compensating events for the full difference as **one group**, so you can undo the restore itself.
  - Bank-sync transactions created after T are included in the difference, and the next fetch will offer them again as new.
- **Retention:** forever. Snapshots handle performance.
- **Redaction (the one exception to immutability):** for when a card or account number got into the data anyway. "Redact field" replaces that field's value with `[redacted]` in **every past event and snapshot**, then appends a `Redacted` event recording who, when, and which events (but not the value). Redaction is not revertable and syncs to the other device.
