# Asset tracking, amortization, and cost-per-use

- **Status:** closed
- **Type:** `wayfinder:grilling`
- **Map:** [Budget business logic](../map.md)
- **ADR:** [0001 Event log as the source of truth](../../adr/0001-event-log-source-of-truth.md)
- **Depends on:** [Transactions, Review, and Business Tags](09-transactions-review-business-tags.md), [Event log structure and merge rules](06-event-log-and-merge.md), [Targets, automation, and predicted expenses](08-targets-and-automation.md)

## Question

How does the budget track physical assets (e.g. laptops, vehicles, tools, equipment) and their ongoing usage/amortization, evaluate cost-per-day and cost-per-use, handle retirement/resale, and link to replacement targets without compromising the zero-based cash budget?

## Resolution

### 1. Core Principle: Analytical Overlay

- **Zero-based cash budgeting is untouched.** When an asset is acquired, the cash outflow is categorized to its normal budget envelope (e.g., "Tech & Hardware", "Vehicles") and reduces cash and account balances immediately.
- The `Asset` domain entity is an **analytical overlay** on top of the budget. It tracks the durable value, expected lifespan, and utility delivered over time or across discrete uses.

### 2. Domain Model: `Asset` and `AssetUseLog`

#### `Asset` Entity
- `id`: UUIDv7
- `name`: string (e.g., "16-inch MacBook Pro", "Winter Boots")
- `status`: `active`, `retired` (broken, discarded, or donated), or `sold`
- `acquiredDate`: YYYYMMDD
- `initialCostCents`: integer cents (supports manual entry for pre-budget assets, or pre-filled from linked transaction)
- `resaleProceedsCents`: integer cents (default 0; recorded when sold)
- `expectedLifespanDays`: optional integer (or calculated from expected retirement date)
- `retiredDate`: optional YYYYMMDD
- `memo`: optional string
- `linkedTransactionLineIds`: set of UUIDs of transaction lines (split lines or full transactions) representing acquisition cost, upgrades, or major repairs
- `replacementTargetCategoryId`: optional category UUID linked for replacement funding

#### `AssetUseLog` Entity
- `id`: UUIDv7
- `assetId`: UUIDv7
- `loggedAt`: ISO 8601 / HLC timestamp
- `note`: optional string (e.g., "Client photo shoot", "Trip to mountains")

### 3. Cost-of-Ownership & Value Metrics

All money calculations use integer cents.
- **Cost Basis:**
  - `Total Cost = initialCostCents + sum(linked upgrade/repair transactions)`
  - `Net Cost = Total Cost - resaleProceedsCents`
- **Time-based Amortization (Continuous):**
  - `Days Active = (retiredDate ?? today) - acquiredDate + 1`
  - `Cost per Day = Net Cost / Days Active` (formatted as dollars/cents per day)
  - `Cost per Month = Cost per Day * (365.25 / 12)`
  - `Lifespan Progress % = min(100, (Days Active / expectedLifespanDays) * 100)` (if expected lifespan is set)
- **Usage-based Metrics (Discrete):**
  - `Total Uses = count(AssetUseLog where assetId == id)`
  - `Cost per Use = Net Cost / Total Uses` (or `Total Cost` if 0 uses logged / not yet used)

Both metrics (time-based elapsed cost and per-use cost) are calculated for every asset so the user can evaluate both daily hold cost and unit-utility cost.

### 4. Logging Uses (Frictionless)

- **Quick Action:** In the UI (mobile card or desktop table row), a single tap on `+1 Use` logs an `AssetUseLogged` event instantly.
- **Optional Note:** Long-press or detail view allows adding a short note to the use entry.
- **History View:** Asset detail view displays an expandable timeline of all recorded uses and linked cost events.

### 5. Sinking Fund / Target Bridge

- An Asset detail screen has a **"Create Replacement Target"** button.
- Tapping it prompts for:
  - Target Category (e.g. "Electronics Replacement")
  - Target Amount (defaults to `Total Cost`)
  - Target Due Date (defaults to `acquiredDate + expectedLifespanDays`)
- Creates a standard `One-time by date` Target in the specified category (per ticket 08).
- The action is explicit and user-triggered (never auto-synced or silently altered).

### 6. Event Log Integration

New event types added to the HLC-ordered event log (ticket 06):
- `AssetCreated{id, name, acquiredDate, initialCostCents, expectedLifespanDays, memo}`
- `AssetFieldsSet{id, fields}`
- `AssetTransactionLinked{assetId, transactionLineId}`
- `AssetTransactionUnlinked{assetId, transactionLineId}`
- `AssetUseLogged{id, assetId, note?}`
- `AssetUseDeleted{id}`
- `AssetSold{assetId, soldDate, resaleProceedsCents}`
- `AssetRetired{assetId, retiredDate}`
- `AssetDeleted{id}`

All events follow field-level last-writer-wins and are fully revertable in Change History.
