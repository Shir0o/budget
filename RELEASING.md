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

Under **Settings → Secrets and variables → Actions**:

| Secret                    | Purpose                                                              |
| ------------------------- | -------------------------------------------------------------------- |
| `ANDROID_KEYSTORE_BASE64` | `base64` of the upload keystore (`~/.keystores/my-key.keystore`).     |
| `KEY_ALIAS`               | Alias of the upload key inside the keystore (`my-key-alias`).         |
| `KEY_PASSWORD`            | Password for the upload key.                                          |
| `STORE_PASSWORD`          | Password for the keystore file itself.                                |
| `PLAY_SUPPLY_JSON_KEY`    | Play Console service-account JSON (`~/release-please-supply-key.json`). |

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

The Play Developer API cannot create an app, and it rejects uploads for a package that has
never been published. So, once, by hand:

1. **Create the app** in the Play Console with package name `io.github.shir0o.budget`.
2. **Upload an AAB once by hand** (Internal testing → Create new release) so the package
   exists. Let **Play App Signing** handle the app-signing key (default).
3. **Settings → API access** → link the service account named in
   `PLAY_SUPPLY_JSON_KEY` and grant it **Release Manager** for this app.
4. Add at least one internal tester and publish the internal track once, so testers have a
   join link.

After that, every tag publishes a completed internal-testing release automatically.

## Verifying a release

- **GitHub**: `https://github.com/Shir0o/budget/releases/tag/v1.0.0` should list
  `app-release.aab`, `app-release.apk`, `budget-macos.dmg`, `budget-macos.zip`.
- **Play Console**: Internal testing shows the new version with status **Available to
  internal testers** (not "Draft"). The service account can also be checked without the UI:
  `fastlane supply --track internal --json` read-only inspection, or the Play Developer API
  `edits.tracks.get` for `internal`.
- **The run summary** of the Release workflow repeats both results.

## Notes and limitations

- **macOS builds are unsigned.** No Apple Developer ID certificate or notarization secrets are
  configured, so Gatekeeper will ask the user to right-click → Open on first launch. Ticket 15
  planned a notarized DMG; adding `MACOS_CERTIFICATE_*` / `NOTARY_*` secrets and an
  `xcrun notarytool` step is the follow-up.
- **No release-please yet.** Version bumps and tags are manual (step 2). Ticket 16 planned
  release-please with Conventional Commits; it needs a `RELEASE_PLEASE_TOKEN` PAT because tags
  pushed with `GITHUB_TOKEN` do not trigger `release.yml`. Until then, a tag push is the whole
  release trigger.
- **Tags are data.** The tag reaches shell steps through `TAG`/`VERSION_*` environment
  variables and is validated as `vMAJOR.MINOR.PATCH` before it is used.
- **Pre-release tags** (`-rc`, `-beta`) are not special-cased yet; don't tag them until the
  workflow learns to skip the Play upload.
