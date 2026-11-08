# Contributing

Thanks for helping. A few rules keep Răboj safe and easy to build.

## Build

Only the Xcode Command Line Tools are needed (`xcode-select --install`), macOS 14+.

```sh
make test     # unit tests (Swift Testing)
make verify   # build Raboj.app, sign ad hoc, check entitlements
make run      # open the built app
```

`.build` can get stale after a release build; if the compiler reports missing macro plugins, run `make clean`.

## Rules

- **No `@State` in SwiftUI views.** In current SDKs it is a macro whose plugin ships only with full Xcode, and Homebrew builds Răboj with the Command Line Tools. Use `@StateObject` with a small `ObservableObject`. `make lint` enforces this.
- **New providers need an official or local source.** A documented usage API, or logs the tool writes on the user's Mac. Do not read other apps' credentials, cookies or keychain items.
- **Network only through `GuardedClient`.** Add the provider's hosts to `Provider.allowedHosts`; nothing else may open connections.
- **Decode only what is shown.** Log parsers must not read message content into models.
- **Tests use synthetic fixtures.** Never commit real logs, keys or account data.

## Pull requests

Branch from `staging`, open a PR to `staging`, keep CI green. Code, comments and PR text in English.

## Checking numbers against real logs

```sh
swift run Raboj --report claude ~/.claude
swift run Raboj --report codex ~/.codex
```

## README screenshots

The images in `docs/images` are rendered from made-up demo data, never from real usage:

```sh
swift run Raboj --screenshots docs/images
```
