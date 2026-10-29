# Open-source repo settings

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)

## Question

How is the public repository set up: license, visibility, org standards, protections, and the guardrails that keep real financial data out of it?

## Resolution

### Identity

- **Repo:** `Shir0o/budget`, **public**. The working product name is "Budget". Branding is not part of this map.
- **License:** **MIT**, matching most `Shir0o` repos.
- **Contributions:** inbound = outbound. No CLA or DCO.

### Org standards (`~/.github-repo`)

- **Registration:** register as `"budget|2|flutter|no|Shir0o/budget"` **for now** (Tier 2: no CI yet). The Flutter CI template fails on a repo with no `pubspec.yaml` or tests. The first PR that adds `budget_core` promotes the repo to **Tier 1** (CI + 1 review + linear history) and adds the `no-real-data` CI check below.
- **Files:** add a `PROJECT.md` and run `apply-standards.sh --apply --repo budget`. That brings `AGENTS.md`, `dependabot-flutter.yml`, `CODEOWNERS` (`* @Shir0o`), `SECURITY.md`, and the ruleset file. CodeQL uses GitHub's default setup, not a workflow file. `ci-flutter.yml` arrives with Tier 1.
- **Merging:** squash only, delete branches automatically, default branch `main`. Releases via release-please with Conventional Commits.

### GitHub settings

- **Security:** secret scanning **and push protection** on, private vulnerability reporting on, Dependabot alerts and security updates on.
- **Features:** Issues on (the wayfinder map can move there later; see the map's Notes). Wiki, Projects, and Discussions off.
- **Actions:** read-only `GITHUB_TOKEN` by default. Signing keys (Android keystore, Apple notarization) stored as Actions secrets.

### Repo files

- `README.md` (privacy promises in plain words)
- `LICENSE`
- `PRIVACY.md`, which doubles as the Play Store privacy policy. It says **no data collected**, the Data Safety form declares nothing collected or shared, and SimpleFIN and Google Drive appear as user-initiated third parties.
- `CONTEXT.md`, `docs/adr/`, `docs/wayfinder/`

### Real-data guardrails (public repo)

- **`.gitignore`:** `private/`, `*.budgetbackup`, `**/actual-export*.zip`, `**/ynab-export*.zip`, `*.sqlite`.
- **Synthetic fixtures only:** test fixtures live in `packages/*/test/fixtures/` and must be synthetic.
- **CI check (`no-real-data`):** fails if any tracked file contains a Luhn-valid 12–19 digit run, an ABA-valid routing number, or a `simplefin.org` access URL with credentials.

### Legal gates (org standard 7)

| Gate | Status |
|---|---|
| COPPA | No sign-up and no personal data collected by us, so no age gate is needed |
| Session replay | None |
| Email | None |
| Subscriptions / California auto-renewal law | The app is free; any SimpleFIN fee is paid directly to SimpleFIN |
| Fonts | Self-hosted |
| User-generated uploads (DMCA) | None |
