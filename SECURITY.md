# Security

Răboj reads usage data and, for API accounts, holds admin API keys. Please report anything that could expose those.

## Reporting a vulnerability

Open a [private security advisory](https://github.com/MIKALAKE/raboj/security/advisories/new) on GitHub. Please do not open a public issue for security problems.

## What Răboj promises

- **No backend, no telemetry.** The app talks only to the providers you connect.
- **Fixed hosts per provider.** `GuardedClient` refuses any request that is not HTTPS to the provider's allow-listed host (`api.anthropic.com`, `api.openai.com`). Local providers have no hosts at all.
- **Keys in the Keychain.** API keys are stored as Keychain items, read only when a request is made, sent only in request headers, and never logged.
- **Read-only folders.** Folder accounts use security-scoped bookmarks with read-only access to the folder the user picked. Only token counts, model, time, ids and project folder name are decoded; message text is not.
- **Visible access log.** Every request appears in Settings › Access Log.
- **Small, checked permission set.** App Sandbox, outgoing network, read-only user-selected folders. `make verify` prints the entitlements of a build and fails if incoming connections or write access are added.

Anything that breaks one of these is a security bug.
