# Tech stack and module boundaries

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)

## Question

What stack builds Android and macOS from the business logic, and where are the module boundaries so the logic stays independent of the UI?

## Resolution

- **Flutter / Dart, one codebase** for Android (min API 26) and macOS (12+). This matches the org's other apps and the `ci-flutter.yml` template.
- **Dart pub workspace** (monorepo):

| Package | Contents | Depends on |
|---|---|---|
| `packages/budget_core` | **Pure Dart, no Flutter.** Events, projections, budget math (ticket 07), targets and automation (08), review and business report (09), matching (10), revert (11), redaction (13), Actual and YNAB parsers and comparison (14) | none (besides small pure-Dart libraries) |
| `packages/budget_store` | SQLite + SQLCipher event store and snapshots (drift) | core |
| `packages/budget_sync` | Drive `appdata` backend, XChaCha20-Poly1305 (libsodium), key pairing and recovery phrase | core, store |
| `packages/budget_simplefin` | SimpleFIN client and rate-limit budget | core |
| `packages/budget_mcp` | `budget-mcp` stdio binary (`dart_mcp`), macOS only | core, store |
| `app/` | Flutter UI, Keystore/Keychain, WorkManager | all |

- **Money:** `int` cents in a `Money` value type, everywhere. Floating point is never used.
- **Dates:** transaction dates are civil dates (no time zone); event times are HLC.
- **Testing:** `budget_core` carries the worked examples from tickets 07, 08, 10, and 13 as unit tests, using synthetic fixtures only.
- **Fonts and assets:** bundled locally. No runtime `google_fonts` fetching (org privacy rule).
- **Distribution:**
  - **Android:** Play Store, plus a signed APK on GitHub Releases.
  - **macOS:** a notarized DMG on GitHub Releases. Not the Mac App Store, because its sandbox interferes with an MCP binary launched by outside clients and with Keychain sharing.
