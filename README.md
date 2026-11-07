# Răboj

Your AI usage in the macOS menu bar: every provider, every account, side by side.

> **Status: pre-alpha.** Nothing to install yet. Follow the milestones below.

A *răboj* is the Romanian tally stick: a piece of wood shepherds and merchants notched to keep count.
Răboj keeps count of your AI usage the same way, one notch per token. (Pronounced *ruh-BOZH*.)

## What it will do

- Show usage for Claude Code, Codex and more providers in the menu bar, with a popover for details.
- Any number of accounts per provider (e.g. a work and a personal Claude account), each with its own name and color.
- Switch accounts with one key (⌘0 all, ⌘1, ⌘2 …) or ⌥-click the menu bar item.

## Privacy

- **No backend, no telemetry, no analytics.** Răboj talks only to the providers you connect, never to a server of ours.
- **You connect each account yourself.** Nothing is read until you choose a folder or add a key.
- **Official sources first.** Local usage logs your tools already write, and each provider's documented usage API.
- **Secrets stay in your Keychain.** API keys are stored in the macOS Keychain and sent only to that provider.
- **Sandboxed.** The app can open outgoing connections and read the folders you pick, nothing else. Run `make verify` to see the exact permissions of a build.

## Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`), macOS 14 or later.

```sh
git clone https://github.com/MIKALAKE/raboj.git
cd raboj
make test      # unit tests
make verify    # build Raboj.app, sign it ad hoc, print its permissions
make install   # copy to ~/Applications
```

Homebrew and a DMG on GitHub Releases are planned for the first release.

## Support

Răboj is free and MIT licensed. If it saves you time, a Buy Me a Coffee link will be here at the first release.

## License

[MIT](LICENSE)
