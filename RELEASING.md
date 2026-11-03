# Releasing Budget

The release pipeline ships:

- **Android** — a signed `app-release.aab` + `app-release.apk` on the GitHub Release, and the
  AAB uploaded to the Google Play Console **internal testing** track as a **live release**
  (`release_status: completed`, **not a draft**), so internal testers can install it as soon
  as the upload finishes.
- **macOS** — `budget-macos.dmg` (with an `/Applications` shortcut) and `budget-macos.zip` on
  the GitHub Release.

Production promotion on Play stays a manual click in the Play Console.

## How a release happens

1. Merge the work you want to ship to `main`.
2. Bump `version` in `app/pubspec.yaml`, then tag the merge commit:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

   The tag is the only trigger. It must be a plain `vMAJOR.MINOR.PATCH`; anything else fails
   the workflow before a build starts.
3. `.github/workflows/release.yml` fires:
   - **Create the GitHub Release** — `v1.0.0`, published (not draft), with generated notes.
   - **Android** — assembles `app/android/key.properties` from secrets, derives the Android
     `versionCode` from the tag (`major*10000 + minor*100 + patch`, e.g. `v1.0.0` → `10000`),
     builds the signed AAB + APK, attaches both to the release, writes the Play "what's new"
     text from `CHANGELOG.md` (falls back to "Bug fixes and improvements."), and runs
     `fastlane play_upload` against the internal track with `release_status: "completed"`.
   - **macOS** — builds the release app and attaches `budget-macos.dmg` + `budget-macos.zip`.
   - **Release summary** — the run summary says whether the build was added to Play internal
     testing and whether the macOS assets were attached. The job fails if either platform
     did not ship.

The build number is never stored in source: it is derived from the tag on every run, so the
same tag always produces the same `versionCode`.

## Required GitHub secrets

Already configured for this repo. Under **Settings → Secrets and variables → Actions**:

| Secret                    | Purpose                                                              |
| ------------------------- | -------------------------------------------------------------------- |
| `ANDROID_KEYSTORE_BASE64` | `base64` of the upload keystore (`~/.keystores/my-key.keystore`).     |
| `KEY_ALIAS`               | Alias of the upload key inside the keystore (`my-key-alias`).         |
| `KEY_PASSWORD`            | Password for the upload key.                                          |
| `STORE_PASSWORD`          | Password for the keystore file itself.                                |
| `PLAY_SUPPLY_JSON_KEY`    | Play Console service-account JSON (`~/release-please-supply-key.json`). |

The macOS signing secrets (`MACOS_CERTIFICATE_BASE64`, the notarization credentials) are optional
and documented under [macOS signing](#macos-signing).

The workflow fails fast, naming the missing secrets, if any are absent. It never prints their
values, and deletes every mounted credential file under `if: always()`.

Seeding them (only if this app shares the upload keystore and service account already used by
the other `Shir0o` apps):

```bash
base64 -i ~/.keystores/my-key.keystore | tr -d '\n' | \
  gh secret set ANDROID_KEYSTORE_BASE64 --repo Shir0o/budget
gh secret set KEY_ALIAS --repo Shir0o/budget --body "my-key-alias"
gh secret set KEY_PASSWORD --repo Shir0o/budget --body "<key password>"
gh secret set STORE_PASSWORD --repo Shir0o/budget --body "<store password>"
gh secret set PLAY_SUPPLY_JSON_KEY --repo Shir0o/budget < ~/release-please-supply-key.json
```

## One-time Play Console setup

The Play Developer API cannot create an app, so this part is manual. It is **already done** for
this repo: the app `io.github.shir0o.budget` exists, the service account in
`PLAY_SUPPLY_JSON_KEY` is linked with Release Manager, and v1.0.0 (versionCode 10000) is on the
internal track with status `completed`.

For a new app, once, by hand:

1. **Create the app** in the Play Console with package name `io.github.shir0o.budget`.
2. Let **Play App Signing** handle the app-signing key (default).
3. **Settings → API access** → link the service account named in
   `PLAY_SUPPLY_JSON_KEY` and grant it **Release Manager** for this app.
4. Add at least one internal tester, so they have a join link.

The CI upload does not need a hand-made first release: it created the first internal-testing
release for this app directly.

## Verifying a release

- **GitHub**: `https://github.com/Shir0o/budget/releases/tag/v1.0.0` should list
  `app-release.aab`, `app-release.apk`, `budget-macos.dmg`, `budget-macos.zip`.
- **Play Console**: Internal testing shows the new version with status **Available to
  internal testers** (not "Draft"). The service account can also be checked without the UI:
  `fastlane supply --track internal --json` read-only inspection, or the Play Developer API
  `edits.tracks.get` for `internal`.
- **The run summary** of the Release workflow repeats both results.

## macOS signing

- **macOS is ad-hoc signed by default.** Without Apple secrets the DMG still ships and runs, but
  Gatekeeper asks the user to right-click → Open on first launch. Add the Developer ID secrets
  below to sign and notarize automatically. Ticket 15 planned a notarized DMG; this is that step.

### Signing and notarizing the macOS build

You need a paid **Apple Developer Program** membership. The certificate must be **Developer ID
Application** — the "Apple Development" and "Apple Distribution" certificates in your keychain are
for development and the Mac App Store, not for a DMG downloaded from GitHub.

There are two websites involved and it matters which one:

- **developer.apple.com/account** — certificates. *App Store Connect has no certificate page.*
- **appstoreconnect.apple.com** — the notarization API key (optional auth route).

#### 1. Create the Developer ID Application certificate

Either Xcode (fastest):

1. Xcode → Settings → Accounts → select the team → **Manage Certificates…** → **+** →
   **Developer ID Application**.

Or the developer website (if you are not using Xcode for this):

1. Keychain Access → menu **Keychain Access** → **Certificate Assistant** → **Request a
   Certificate From a Certificate Authority…** → *Saved to disk* → save `CertificateSigningRequest.certSigningRequest`.
   This creates the private key in your login keychain; the certificate must be created from **this
   Mac** or the private key will not match.
2. developer.apple.com/account → **Certificates, Identifiers & Profiles** → **Certificates** →
   **+** → **Developer ID Application** → choose the **Account Holder / Admin** team → upload the
   CSR → **Continue** → **Download**.
3. Double-click the downloaded `.cer` to install it into your login keychain. It pairs with the
   private key from step 1.
4. Check it is there:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

5. **Export it.** Keychain Access → **My Certificates** → right-click *Developer ID Application:
   Your Name (TEAMID)* → **Export…** → save as `DeveloperID.p12` with a password. The export must
   include the private key; if the disclosure triangle does not show a private key under the
   certificate, the CSR came from another Mac.

#### 2. Pick a notarization credential

**Route A — App Store Connect API key (recommended for CI).**

1. appstoreconnect.apple.com → **Users and Access** → **Integrations** (older accounts: **Keys**) →
   **App Store Connect API** → **Team Keys**.
2. Note the **Issuer ID** shown above the key list.
3. **+** → name it `budget-notary`, role **Developer** (Admin also works) → **Generate**.
4. **Download the `.p8` immediately** — Apple lets you download it exactly once. Note its **Key ID**.
5. Secrets:

   ```bash
   gh secret set NOTARY_KEY_P8 --repo Shir0o/budget < AuthKey_XXXXXXXXXX.p8
   gh secret set NOTARY_KEY_ID --repo Shir0o/budget --body "<10-character key id>"
   gh secret set NOTARY_ISSUER_ID --repo Shir0o/budget --body "<issuer uuid>"
   ```

**Route B — Apple ID + app-specific password.**

1. appleid.apple.com → Sign-In and Security → **App-Specific Passwords** → create one named
   `budget-ci`.
2. developer.apple.com/account → **Membership details** → *Team ID* (10 characters).
3. Secrets:

   ```bash
   gh secret set APPLE_ID --repo Shir0o/budget --body "<your Apple ID email>"
   gh secret set APPLE_APP_PASSWORD --repo Shir0o/budget --body "<app-specific password>"
   gh secret set APPLE_TEAM_ID --repo Shir0o/budget --body "<10-character team id>"
   ```

If both routes are configured, **Route A wins** (`NOTARY_KEY_ID` takes precedence). The workflow
fails fast and names any missing secret for whichever route you chose.

#### 3. Add the certificate secrets

```bash
base64 -i DeveloperID.p12 | tr -d '\n' | \
  gh secret set MACOS_CERTIFICATE_BASE64 --repo Shir0o/budget
gh secret set MACOS_CERTIFICATE_PASSWORD --repo Shir0o/budget --body "<p12 password>"
```

`MACOS_SIGNING_IDENTITY` is optional; set it only if you need to pin an exact identity string
(for example when the certificate is not the only one that matches).

#### 4. Push a tag

The macOS job then:

- imports the `.p12` into a throwaway keychain (`security import`, partition list set for
  `codesign`),
- re-signs `Budget.app` with the Developer ID identity, the hardened runtime
  (`--options runtime`) and `app/macos/Runner/Release.entitlements` — this also drops the
  `get-task-allow` entitlement that ad-hoc signing leaves behind,
- notarizes the app with `xcrun notarytool submit --wait` and staples the ticket,
- builds the DMG and ZIP (both contain the stapled app),
- notarizes and staples the DMG,
- deletes the keychain and the temporary `.p8`, and only then uploads the assets.

If `MACOS_CERTIFICATE_BASE64` is unset, none of this runs and the release keeps shipping the
ad-hoc build, exactly as before.

Notarization needs Apple's service, so the macOS job takes roughly 5–15 minutes longer.

### Checking the signature yourself

```bash
hdiutil attach budget-macos.dmg
codesign -dvvv /Volumes/Budget/Budget.app   # expect Authority=Developer ID Application: … and flags=…(runtime)
spctl --assess --type execute -vv /Volumes/Budget/Budget.app   # expect "accepted, Notarized Developer ID"
xcrun stapler validate /Volumes/Budget/Budget.app
xcrun stapler validate budget-macos.dmg
```

## Notes and limitations

- **No release-please yet.** Version bumps and tags are manual (step 2). Ticket 16 planned
  release-please with Conventional Commits; it needs a `RELEASE_PLEASE_TOKEN` PAT because tags
  pushed with `GITHUB_TOKEN` do not trigger `release.yml`. The secret now exists, so wiring up
  `.github/workflows/release-please.yml` is a small follow-up. Until then, a tag push is the
  whole release trigger.
- **Tags are data.** The tag reaches shell steps through `TAG`/`VERSION_*` environment
  variables and is validated as `vMAJOR.MINOR.PATCH` before it is used.
- **Pre-release tags** (`-rc`, `-beta`) are not special-cased yet; don't tag them until the
  workflow learns to skip the Play upload.

## Release history

| Tag      | Published  | Android                                   | macOS                            |
| -------- | ---------- | ----------------------------------------- | -------------------------------- |
| `v1.0.0` | 2026-11-02 | versionCode 10000, Play internal `completed` | `budget-macos.dmg` + `.zip`      |
