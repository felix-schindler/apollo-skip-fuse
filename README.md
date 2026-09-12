**The Apollo GraphQL runtime — client, normalized cache, and transport backends — built for Android through [Skip Fuse](https://skip.dev/docs/modes/), without breaking iOS, macOS, watchOS, tvOS, or visionOS.**

> [!NOTE]
> This is `felix-schindler/apollo-skip-fuse`, a fork of [`apollographql/apollo-ios`](https://github.com/apollographql/apollo-ios) at **v2.4.0**, carrying the runtime package only. Upstream docs, code generation, and releases still live at `apollographql/apollo-ios`; Android support here is a work in progress.

## Using this fork

Add the package to your `Package.swift`:

```swift
dependencies: [
    // Until the first fork release is tagged, track `main`.
    .package(url: "https://github.com/felix-schindler/apollo-skip-fuse.git", branch: "main"),
],
```

Link the `Apollo` product to every target that uses `ApolloClient`:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Apollo", package: "apollo-skip-fuse"),
    ]
)
```

Targets that only use Apollo's generated models don't need the `Apollo` product. For schema and code-generation workflows, follow the [upstream Getting Started guide](https://www.apollographql.com/docs/ios/get-started). The CLI is the standard prebuilt binary; `make` unpacks `CLI/apollo-ios-cli.tar.gz` into `./apollo-ios-cli`.

> **Codegen rewrites nested package manifests.** The CLI's `swiftPackage` module type always writes a `Package.swift` depending on upstream `apollographql/apollo-ios` at `exact: "2.4.0"`. If your generated module is its own package (e.g. `GitLabAPI/`), re-apply the fork dependency after every `./apollo-ios-cli generate` (then `swift package resolve`), or switch that module to a non-`swiftPackage` type. Otherwise resolution mixes upstream and fork copies of the same targets and fails with "multiple similar targets".

## What's in the package

Runtime package only — no code-generation sources, no CLI sources, no upstream test suite:

| Target | Description | Depends on |
| ----- | ----- | ----- |
| `ApolloAPI` | Protocols and types consumed by generated models | — |
| `Apollo` | Client, request chain/interceptors, normalized cache | `ApolloAPI` |
| `ApolloSQLite` | SQLite cache backend | `Apollo` |
| `ApolloWebSocket` | WebSocket transport backend | `Apollo` |
| `ApolloTestSupport` | Mocks for generated models | `Apollo`, `ApolloAPI` |

All targets use Swift 6 language mode. The public API is consumed by user-generated code from the standard Apollo CLI, so source-breaking changes are avoided.

## Status

All five targets build for Android, the platform-neutral tests in `Tests/` pass on-device with `skip android test`, and a real Skip Fuse app (Apollo + generated models + SkipFuseUI) compiles, installs, and launches on Android 12. The SQLite cache has been verified at runtime on Android, and networking, subscriptions, and the non-Darwin streaming fallback have been exercised there too. [AGENTS.md](AGENTS.md) has the porting notes and current open items.

## Building and testing

```sh
swift build && swift test        # Apple platforms, tests on macOS
skip android build               # Android cross-compile
skip android test                # Android tests (device or emulator)
```

- Apple builds use Xcode's Swift toolchain; Android builds need [Skip CLI 1.9.8](https://skip.dev) plus the Swift Android SDK.
- `swift test` runs `ApolloAPITests`, `ApolloSQLiteTests`, and `ApolloWebSocketTests`. The full upstream Apollo test suite lives in [`apollographql/apollo-ios-dev`](https://github.com/apollographql/apollo-ios-dev) and cannot be run from this repo.
- Don't run `swift build --swift-sdk ...` with the default `swift` in `PATH` — it picks Xcode's toolchain and fails with a misleading error. `skip android build` selects the matching Swiftly 6.3.3 toolchain; `skip doctor` diagnoses a broken Skip environment.
- CI (`.github/workflows/ci.yml`) runs the macOS tests plus an Android emulator build/test job.

## Releases

Fork tags use a `v` prefix (`v2.4.1`), while upstream tags are bare numbers (`2.4.0`), so they don't collide. To release, add `changelogs/vX.Y.Z.md`, then tag and push:

```sh
git tag vX.Y.Z && git push origin vX.Y.Z
```

`.github/workflows/release.yml` creates the GitHub release from that changelog. `ApolloClientVersion` in `Sources/Apollo/Constants.swift` stays in sync with the bundled CLI tarball; `scripts/cli-version-check.sh` verifies it.

## Documentation and help

- [Apollo iOS documentation](https://www.apollographql.com/docs/ios) · [Getting Started](https://www.apollographql.com/docs/ios/get-started) · [API reference](https://www.apollographql.com/docs/ios/docc/documentation) · [VS Code extension](https://marketplace.visualstudio.com/items?itemName=apollographql.vscode-apollo)
- [Skip Fuse](https://skip.dev/docs/modes/) · [Skip porting guide](https://skip.dev/docs/porting/) · [Skip module catalog](https://skip.dev/docs/modules/)
