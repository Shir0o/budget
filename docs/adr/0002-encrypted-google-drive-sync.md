# 0002 Encrypted sync through Google Drive app data

- **Status:** accepted (2026-10-29)

## Context

Sync is for one person (Android and Mac). The privacy requirements are: no account with us, no server we run, and the storage provider must not be able to read the budget. The user picked Google Drive. Drive is not private by default; Google can read plaintext files.

## Decision

Each device appends only its own encrypted event segments to the Drive **`appDataFolder`** (`drive.appdata` scope). Everything is sealed with a per-budget 256-bit key (XChaCha20-Poly1305). The key moves between devices only by QR code, and a 24-word recovery phrase backs it up.

## Consequences

- Google sees only random file names, sizes, and timing.
- No server to run, and no account with us.
- If you lose every device *and* the recovery phrase, synced data cannot be recovered. That's intentional, and the UI says so.
- Narrowest scope: the app cannot read the user's other Drive files.
- Requires a Google account and a Google Cloud OAuth client (the Drive API on both Android and macOS).

## Alternatives rejected

- **Our own relay server:** an operating burden and a trust burden for a single user.
- **Syncthing / any folder:** private, but requires extra setup on Android. Could become a second backend later behind the same segment interface.
- **iCloud:** poor Android support.
