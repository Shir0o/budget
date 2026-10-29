# Sync, encryption, and keys

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)
- **ADR:** [0002 Encrypted sync through Google Drive app data](../../adr/0002-encrypted-google-drive-sync.md)

## Question

How do one person's Android and Mac sync through Google Drive without Google being able to read the budget? And how are keys created, shared, and recovered?

## Resolution

### Storage

- **On the device:** an SQLite database encrypted with SQLCipher. Its key is stored in Android Keystore or the macOS Keychain.
- **App lock:** optional biometric or passcode lock.
- **In Drive:** the Google Drive API with the **`drive.appdata` scope only**: a hidden app folder. The app cannot see your other Drive files, and you cannot see these files in Drive.

### Layout in Drive

```
appDataFolder/<budgetId>/
  <deviceId>/seg-<seq>.bin        append-only event segments (≤ 500 events each)
  <deviceId>/snap-<hlc>.bin       periodic snapshot
  manifest-<deviceId>.json        device name + latest seq (encrypted body)
```

- **Writes:** each device writes **only its own** folder, so no file is ever written by two devices. Devices download each other's segments and merge them (ticket 06).
- **Encryption:** every file is sealed with **XChaCha20-Poly1305** using the **Budget Key** (random 256-bit, one per budget). File names reveal only random ids.
- **When it syncs:** on app open, after local changes (with a 30 s delay to batch them), and every 6 hours in the background. It works offline and catches up later.

### Keys

- **Budget Key:** created on the first device when you turn sync on.
- **Adding the second device:** the first device shows a **QR code** containing the Budget Key and the Drive budget id. The second device scans it. Nothing passes through a server.
- **Recovery phrase:** a 24-word BIP39 encoding of the Budget Key, shown once when you turn sync on, and again in Settings after biometric confirmation. It's the only way back if every device is lost.
- **Rotating the key** (for example, after losing a phone): generate a new key, re-encrypt a fresh snapshot, delete the old segments, and re-pair the remaining device.

### Backup and export (no lock-in)

- **Encrypted backup:** a manual `.budgetbackup` file (the event log, sealed with the Budget Key).
- **Plain export:** CSV (transactions, Plan-style monthly assignments) and JSON (full state).

Sync is off by default. The app works fully without it.
