<header>
  <div align="center">
    <a href="https://www.apollographql.com?utm_medium=github&utm_source=apollographql_apollo-client&utm_campaign=readme"><img src="https://raw.githubusercontent.com/apollographql/apollo-client-devtools/main/assets/apollo-wordmark.svg" height="100" alt="Apollo Logo"></a>
  </div>
  <h1 align="center">Apollo iOS — Android via Skip Fuse (fork)</h1>

**The industry-leading GraphQL client in Swift, now targeting Android as well as iOS, macOS, watchOS, tvOS, and visionOS.** Powerful caching, robust code generation, and intuitive APIs to accelerate your app development — from a single Swift package.

  <div align="center">
  <br>

  <a href="https://raw.githubusercontent.com/apollographql/apollo-ios/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-lightgrey.svg?maxAge=2592000" alt="MIT license">
  </a>
  <a href="#requirements">
    <img src="https://img.shields.io/badge/platforms-iOS%2015%2B%20%7C%20macOS%2012%2B%20%7C%20tvOS%2015%2B%20%7C%20watchOS%208%2B%20%7C%20visionOS%201%2B%20%7C%20Android-333333.svg" alt="Supported Platforms: iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+, Android" />
  </a><br><br>

  <a href="https://github.com/apple/swift">
    <img src="https://img.shields.io/badge/Swift-6-orange.svg" alt="Swift 6 supported">
  </a>
  <a href="https://swift.org/package-manager/">
    <img src="https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square" alt="Swift Package Manager compatible">
  </a>
  <a href="https://skip.dev/docs/modes/">
    <img src="https://img.shields.io/badge/Skip-Fuse-blue?style=flat-square" alt="Skip Fuse compatible">
  </a>

  </div>
</header>

> **Fork notice:** This is `felix-schindler/apollo-skip-fuse`, a fork of [`apollographql/apollo-ios`](https://github.com/apollographql/apollo-ios) at **v2.4.0** (runtime package only). Fork goal: make this package build and run on **Android via [Skip Fuse](https://skip.dev/docs/modes/)** without breaking the Apple platforms. Upstream docs, codegen, and releases still live at `apollographql/apollo-ios`; Android support here is work in progress.

## ❓ Why this fork?

✅ **Same Apollo iOS API on Android** — reuse your models, cache, and networking code across platforms<br>
✅ **Intuitive caching** — intelligent in-memory or SQLite out of the box<br>
✅ **Highly configurable code generation** — no hand-written models for network responses<br>
✅ **Opinionated** — leads users down the "pit of success" by default<br>
✅ **Production-tested core** — built on the Apollo iOS runtime that powers countless apps worldwide<br>

## 📦 Fork scope

Runtime package only. No code generation sources, no CLI sources, no upstream test suite:

| Target | Description |
| ----- | ----- |
| `ApolloAPI` | Protocols/types consumed by generated models. Depends on nothing. |
| `Apollo` | Client, request chain/interceptors, normalized cache. Depends on `ApolloAPI`. |
| `ApolloSQLite` | SQLite cache backend. Depends on `Apollo`. |
| `ApolloWebSocket` | WebSocket transport backend. Depends on `Apollo`. |
| `ApolloTestSupport` | Mocks for generated models. Depends on `Apollo` + `ApolloAPI`. |

All targets use Swift 6 language mode. The public API is consumed by user-generated code from the standard Apollo CLI, so source-breaking changes are avoided.

Codegen is unchanged: use the standard Apollo iOS CLI (prebuilt binary). `make` unpacks `CLI/apollo-ios-cli.tar.gz`, and the `InstallCLI` command plugin downloads the matching CLI on demand. The full upstream test suite lives in [`apollographql/apollo-ios-dev`](https://github.com/apollographql/apollo-ios-dev) — `Tests/` here contains platform-neutral tests for this fork (see below).

## 🛠️ Requirements

- Apple builds: Xcode Swift toolchain (`swift build` from the repo root).
- Android builds: [Skip CLI 1.9.8](https://skip.dev) (`skip android build`). This cross-compiles `aarch64-unknown-linux-android28` with the Swift Android SDK and passes `-DSKIP_BRIDGE -DTARGET_OS_ANDROID`.
- Android tests: a connected device or emulator (`skip android test`).

## 🚀 Quick Start

### Add this fork to your dependencies

```swift title="Package.swift"
dependencies: [
    .package(
        url: "https://github.com/felix-schindler/apollo-skip-fuse.git",
        .upToNextMajor(from: "2.4.0")
    ),
],
```

### Link the Apollo product to your package target

Any targets in your application that will use `ApolloClient` need a dependency on the `Apollo` product.

```swift title="Package.swift"
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Apollo", package: "apollo-skip-fuse"),
    ]
)
```

> **Note:** Targets that only use Apollo's generated models don't need to be linked to the `Apollo` product. For codegen and schema workflows, follow the [upstream Getting Started guide](https://www.apollographql.com/docs/ios/get-started?utm_source=github&utm_medium=apollographql_apollo-client&utm_campaign=readme).

## ✅ Build and verify

Minimum verification for every change is **both**:

```sh
swift build
swift test
skip android build
```

- `swift build` builds all targets for Apple platforms (fast).
- `swift test` runs the platform-neutral tests in `Tests/` (`ApolloAPITests`, `ApolloSQLiteTests`, `ApolloWebSocketTests`) on macOS.
- `skip android build` builds for Android, and `skip android test` runs the same tests on a connected device or emulator. `skip doctor` diagnoses a broken Skip environment.
- Do **not** run `swift build --swift-sdk ...` with the default `swift` in `PATH`: it uses Xcode's toolchain and fails with the misleading `compiled module was created by an older version of the compiler`. `skip android build` selects the matching Swiftly 6.3.3 toolchain.
- For behavior changes, extend the platform-neutral tests in `Tests/` where reasonable. The full upstream Apollo test suite cannot be run from this repo.
- CI (`.github/workflows/ci.yml`) runs `swift build` + `swift test` on macOS and builds/tests on an Android emulator.

## 🤖 Android porting notes

Following Skip's [porting guide](https://skip.dev/docs/porting/) and [module catalog](https://skip.dev/docs/modules/). Repo-specific facts already verified:

- This is a **Fuse** (native Swift) target, not Lite/transpiled Kotlin. Foundation gaps are fixed with `canImport`/`FoundationNetworking`, not Skip Lite frameworks (e.g. SkipFoundation, SkipUI).
- On Android, `Foundation` splits networking into `FoundationNetworking`. Files using `URLSession`, `URLRequest`, `URLResponse`, or `HTTPURLResponse` need:

```swift
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
```

- `URLSession.bytes(for:)` / `AsyncBytes` does not exist in Android's `FoundationNetworking`. The chunked/multipart response path (`ApolloURLSession`, `AsyncHTTPResponseChunkSequence`) uses a `dataTask`/delegate-based fallback on non-Darwin platforms (`URLSessionDataTaskChunkLoader`, `AsyncHTTPResponseChunkSequence+NonDarwin.swift`), kept behaviorally in sync with the Darwin implementation.
- `URLSessionWebSocketTask` compiles and works on Android (verified on-device against a live echo server), so `ApolloWebSocket` needed only the `FoundationNetworking` import.
- `JSONSerialization` returns Swift `[String: Any]`/`[Any]` on Android instead of `NSDictionary`/`NSArray`. Nested JSON is read through `JSONValueConversion` (`ApolloAPI` `@_spi(Internal)`) rather than direct casts — never cast its output with `as! JSONValue` / `as? JSONObject` / `as? [JSONValue]`.
- `import SQLite3` is unavailable from the Android Swift SDK. `ApolloSQLite` depends on `SwiftToolchainCSQLite` (used on Android/Linux/Windows) and imports it when `SQLite3` can't be imported; Apple builds keep using the system SQLite.
- Apple-only APIs/constants are gated instead of deleted, e.g. `kCFBundleIdentifierKey`/`kCFBundleVersionKey` in `Sources/Apollo/Internal Utilities/Bundle+Helpers.swift`. Use `#if canImport(...)` / `#if os(Android)` so Apple platforms keep building.

## 📊 Current Android status

All five targets (`ApolloAPI`, `Apollo`, `ApolloSQLite`, `ApolloWebSocket`, `ApolloTestSupport`) build for Android, and the tests in `Tests/` pass on-device with `skip android test`. Re-run `skip android build` / `skip android test` rather than trusting this snapshot.

## 🔖 Versioning

`ApolloClientVersion` in `Sources/Apollo/Constants.swift` is the source of truth; `scripts/get-version.sh` and the CLI download script derive from it. Don't bump it without a matching release, or `InstallCLI` will try to download a nonexistent tarball. This fork tracks upstream `2.4.0`.

## 🚢 Releases

Push tag `vX.Y.Z` → `.github/workflows/release.yml` creates a GitHub release with the body from `changelogs/vX.Y.Z.md`. Release process: add `changelogs/vX.Y.Z.md` → tag and push:

```sh
git tag vX.Y.Z && git push origin vX.Y.Z
```

> **Note:** fork tags use a `v` prefix (`v2.4.1`), while upstream tags are bare numbers (`2.4.0`) — they won't collide. Fork releases don't affect the CLI download, which pulls the upstream tarball by `ApolloClientVersion`.

## 💡 Resources

| Resource | Description | Link |
| ----- | ----- | ----- |
| **Upstream repo** | `apollographql/apollo-ios` releases and issues | [View →](https://github.com/apollographql/apollo-ios) |
| **Getting Started Guide** | Complete setup and first query | [Start Here →](https://www.apollographql.com/docs/ios/get-started?utm_source=github&utm_medium=apollographql_apollo-client&utm_campaign=readme) |
| **Full Documentation** | Comprehensive guides and examples | [Read Docs →](https://www.apollographql.com/docs/ios?utm_source=github&utm_medium=apollographql_apollo-client&utm_campaign=readme) |
| **API Reference** | Complete API documentation | [Browse API →](https://www.apollographql.com/docs/ios/docc/documentation) |
| **VS Code Extension** | Enhanced development experience | [Install Extension →](https://marketplace.visualstudio.com/items?itemName=apollographql.vscode-apollo) |
| **Skip Fuse docs** | Native Swift on Android | [Read →](https://skip.dev/docs/modes/) |
| **Skip porting guide** | Foundation/networking/SQLite gaps | [Read →](https://skip.dev/docs/porting/) |

## 💬 Get Support

- Fork issues (Android port, build failures): open an issue in this repo.
- Upstream Q&A: [**Community Forum**](https://community.apollographql.com?utm_source=github&utm_medium=apollographql_apollo-client&utm_campaign=readme) and [**GraphQL Discord**](https://discord.graphql.org).
- Upstream roadmap: [`ROADMAP.md`](https://github.com/apollographql/apollo-ios/blob/main/ROADMAP.md).

## 🏆 Contributing

Contributions that move Android support forward without breaking Apple platforms or the public API are welcome. For behavior changes, extend the platform-neutral tests in `Tests/` where reasonable, and verify with `swift build` + `swift test` and `skip android build` (see above). For upstream Apollo iOS contributions (codegen, CLI, Apple-only runtime work), see [`apollographql/apollo-ios-dev`](https://github.com/apollographql/apollo-ios-dev/blob/main/CONTRIBUTING.md).

## 🪪 License

Source code in this repository is available under the terms of the MIT License. Read the full text [here](https://github.com/apollographql/apollo-ios/blob/main/LICENSE). Apollo iOS is maintained upstream by the Apollo team; this fork adds Android/Skip support and is not affiliated with or endorsed by Apollo GraphQL.
