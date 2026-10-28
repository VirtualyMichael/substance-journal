# Security policy

Substance Journal holds sensitive personal information, so security and privacy problems are taken seriously.

## Reporting a vulnerability

Please **do not open a public issue** for a security or privacy problem. Use GitHub's private reporting instead:
[Report a vulnerability](../../security/advisories/new). Include what you found, how to reproduce it and what you think the impact is.

You can expect an acknowledgement and a plan; this is a small project maintained by one person, so please allow some time.

## What is in scope

- Anything that lets someone read or change a journal without the pairing key or backup passphrase.
- Flaws in the sync, pairing, backup or restore formats (`SJSYNC1`, `SJPAIR1`, `SJBAK1`).
- The local Wi-Fi sync server accepting requests it should refuse.
- Data leaving a device that should not, including through logs, links or crash output.
- The MCP server (`mcp/substance-journal`) writing or deleting more than it should.

## How the data is protected

- Everything is stored locally. There are no accounts, analytics or telemetry.
- Sync packages and backups are compressed and sealed with AES-256-GCM. The sync key is created when two devices pair; backup keys come from a passphrase with PBKDF2-HMAC-SHA256 (150,000 iterations).
- Wi-Fi sync listens on a local port only while the app is open, and packages are encrypted, so a device without the key can neither read nor change anything.

Reference data errors (a wrong dose, for example) are not security issues; see [CONTRIBUTING.md](CONTRIBUTING.md).
