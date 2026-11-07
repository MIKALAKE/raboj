# Răboj

Your AI usage in the macOS menu bar: every provider, every account, side by side.

A *răboj* is the Romanian tally stick: a piece of wood shepherds and merchants notched to keep count. Răboj keeps count of your AI usage the same way. (Pronounced *ruh-BOZH*.)

> **Status: 0.1, first release candidate.** Feedback and bug reports welcome.

## What it shows

| Provider | How Răboj reads it | What you get |
|---|---|---|
| **Claude Code** | The session logs Claude Code writes in its data folder (`~/.claude`, or any `CLAUDE_CONFIG_DIR`) | Tokens by type, model and project; 5-hour window estimate |
| **Claude plan limits** (Pro, Max, Ultra) | The `rate_limits` Claude Code passes to its [status line](https://code.claude.com/docs/en/statusline), saved by a one-line setting (below) | 5-hour and weekly limit used, reset time |
| **Codex** | The session logs Codex writes in `~/.codex/sessions` (or `CODEX_HOME`) | Tokens by model and project; plan limit used, reset time |
| **Anthropic API** | Official [Admin API usage and cost reports](https://platform.claude.com/docs/en/manage-claude/usage-cost-api) with your Admin key | Billed cost, tokens by model |
| **OpenAI API** | Official [organization usage and costs API](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage) with your Admin key | Billed cost, tokens by model |

Add as many accounts as you like, on any provider: a work and a personal Claude account, several API organizations, and so on. Each account has its own name and color.

- **Menu bar:** the selected account's number, or several pinned accounts side by side.
- **Switch accounts:** ⌘0 for All and ⌘1 … ⌘9 in the popover, or ⌥-click the menu bar item. Right-click for a menu.
- **Popover:** today, 7 or 30 days, change versus the usual, plan limits with reset countdown, 7-day chart, by model, by project.

## Privacy

- **No backend, no telemetry, no analytics.** Răboj talks only to the providers you connect.
- **You connect each account yourself.** Nothing is read until you pick a folder or add a key.
- **Official and local sources only.** No scraping, no browser cookies, no reading other apps' logins.
- **Keys stay in your Keychain** and are sent only to that provider's API host, over HTTPS.
- **Every request is listed** in Settings › Access Log. Folder accounts never use the network.
- **Sandboxed:** outgoing connections and read-only access to the folders you pick, nothing else. `make verify` prints the exact permissions of a build.

See [SECURITY.md](SECURITY.md).

## Install

Răboj is free and does not use a paid Apple Developer account, so builds are signed ad hoc instead of notarized.

### Homebrew (recommended)

Builds from source on your Mac with the Xcode Command Line Tools, so macOS shows no warning:

```sh
brew install mikalake/tap/raboj
ln -sf "$(brew --prefix)/opt/raboj/Raboj.app" ~/Applications/Raboj.app
open ~/Applications/Raboj.app
```

### DMG

Download the DMG from [Releases](https://github.com/MIKALAKE/raboj/releases), check it against the `.sha256` file, and drag Răboj to Applications. The first time you open it, macOS blocks it because it is not notarized: open **System Settings › Privacy & Security** and click **Open Anyway**.

### From source

```sh
xcode-select --install        # once, if you don't have the Command Line Tools
git clone https://github.com/MIKALAKE/raboj.git
cd raboj
make test install             # tests, then installs to ~/Applications
open ~/Applications/Raboj.app
```

## Setting up accounts

- **Claude Code / Codex:** click **+**, pick the provider and choose its data folder in the macOS dialog (it opens at `~/.claude` or `~/.codex`; hidden folders are shown). Using several Claude accounts with `CLAUDE_CONFIG_DIR`? Add one account per folder.
- **Claude plan limits:** in Settings › Accounts › your Claude Code account, copy the status line snippet into that folder's `settings.json`. After your next message in Claude Code, Răboj shows the 5-hour and weekly limits. It replaces any status line you already have.
- **Anthropic / OpenAI API:** paste an organization Admin key and click **Test Connection**. Admin keys are created by organization admins in the Claude Console or the OpenAI platform settings.

## Check the numbers yourself

```sh
swift run Raboj --report claude ~/.claude
swift run Raboj --report codex ~/.codex
```

## Support

Răboj is free and MIT licensed. A Buy Me a Coffee link will be here soon.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
