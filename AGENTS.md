# AGENTS.md

## What this repo is

- Fork of [apollographql/apollo-ios](https://github.com/apollographql/apollo-ios) at v2.4.0 (runtime package only).
- Fork goal: make this package build and run on Android via [Skip Fuse](https://skip.dev/docs/modes/), without breaking the Apple platforms.
- No code generation here. The CLI is a prebuilt binary: `make` unpacks `CLI/apollo-ios-cli.tar.gz` into `apollo-ios-cli`; `scripts/cli-version-check.sh` verifies it matches `ApolloClientVersion`. Upstream's full test suite lives in [apollo-ios-dev](https://github.com/apollographql/apollo-ios-dev); this fork adds small platform-neutral `Tests/ApolloAPITests`, `Tests/ApolloSQLiteTests` and `Tests/ApolloWebSocketTests` targets (see below).
- Targets and dependency direction (all targets are Swift 6 language mode):
  - `ApolloAPI` — protocols/types consumed by generated models; depends on nothing.
  - `Apollo` — client, request chain/interceptors, normalized cache; depends on `ApolloAPI`.
  - `ApolloSQLite`, `ApolloWebSocket` — cache and transport backends; depend on `Apollo`.
  - `ApolloTestSupport` — mocks for generated models; depends on `Apollo` + `ApolloAPI`.
- The public API is consumed by user-generated code from the standard Apollo CLI; avoid source-breaking changes.
- `README.md` is the user-facing entry point and stays short; build, porting, and consumer gotchas belong in this file.

## Consumer integration gotchas

- Skip Fuse apps must depend on this package by URL (`branch: "main"` until a fork release exists). `skipstone` stages the package graph and rewrites remote dependencies to local paths; a relative `.package(path:)` pointing outside the app directory still builds for Apple platforms but breaks Android package resolution during `skip app launch`.
- The CLI's `swiftPackage` module type always rewrites a nested generated `Package.swift` to upstream `apollographql/apollo-ios` at `exact: "2.4.0"`. After every `./apollo-ios-cli generate`, re-apply the fork dependency there and run `swift package resolve`; otherwise resolution mixes upstream and fork copies of the same targets and fails with "multiple similar targets". Switching the generated module off `swiftPackage` avoids the churn.

## Build and verify

- Apple platforms: `swift build` from the repo root (fast; builds all targets).
- Android: `skip android build` (Skip CLI 1.9.8 is installed). It cross-compiles `aarch64-unknown-linux-android28` with the Swift Android SDK and passes `-DSKIP_BRIDGE -DTARGET_OS_ANDROID`.
- Do not run `swift build --swift-sdk ...` with the default `swift` in `PATH`: it uses Xcode's toolchain and fails with the misleading `compiled module was created by an older version of the compiler`. `skip android build` selects the matching Swiftly 6.3.3 toolchain.
- Minimum verification for every change: `swift build` + `swift test` (macOS) and `skip android build` (Android).
- `Tests/ApolloAPITests`, `Tests/ApolloWebSocketTests` and `Tests/ApolloSQLiteTests` are platform-neutral: `swift test` runs them on macOS, and `skip android test` builds the whole package and runs them on a connected device/emulator (one is usually attached here). Upstream's full Apollo suite cannot be run from this repo.
- `.github/workflows/ci.yml` builds and tests on macOS (`swift test`) and on an Android emulator via `skiptools/swift-android-action@v2`. The other workflows are issue triage/security only. `skip doctor` diagnoses a broken local Skip environment.

## Android porting notes

Follow Skip's [porting guide](https://skip.dev/docs/porting/) and [module catalog](https://skip.dev/docs/modules/). Repo-specific facts already verified:

- This is a **Fuse** (native Swift) target, not Lite/transpiled Kotlin. Don't add Skip Lite frameworks (e.g. SkipFoundation, SkipUI) to fill Foundation gaps; fix with `canImport`/`FoundationNetworking` (or SkipSQL for SQLite, which supports Fuse).

- On Android, `Foundation` splits networking into `FoundationNetworking`. Files using `URLSession`, `URLRequest`, `URLResponse` or `HTTPURLResponse` need:

```swift
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
```

- `URLSession.bytes(for:)` / `AsyncBytes` does not exist in Android's `FoundationNetworking` (verified). The non-Darwin fallback lives in `URLSessionDataTaskChunkLoader` (delegate callbacks → `AsyncThrowingStream`) and `AsyncHTTPResponseChunkSequence+NonDarwin.swift` (multipart splitting). Keep them behaviorally in sync with the Darwin `AsyncHTTPResponseChunkSequence`; upstream test vectors for the splitting logic are in `apollo-ios-dev/Tests/ApolloTests/Network/AsyncHTTPResponseChunkSequenceTests.swift`.
- `URLSessionWebSocketTask` works on Android with `FoundationNetworking` (verified on-device against a live echo server over `adb reverse`). `WebSocketTask`/`WebSocketURLSession` are the protocols to mock for transport tests.
- `JSONSerialization` returns Swift `[String: Any]`/`[Any]` on Android, not `NSDictionary`/`NSArray`, and dictionaries with existential values bridge to `NSDictionary` unpredictably. Never cast its output or nested `JSONObject` values with `as! JSONValue` / `as? JSONObject` / `as? [JSONValue]` / `as? [JSONObject]`; use `JSONValueConversion.convert(_:)`, `.jsonObject(from:)`, `.jsonArray(from:)` and `.jsonObjectsArray(from:)` (ApolloAPI `@_spi(Internal)`) instead. These normalize on both platforms; the rest of Apollo reads nested JSON through them.
- `import SQLite3` is not available from the Android Swift SDK (verified). `ApolloSQLite` depends on `SwiftToolchainCSQLite` from [swift-toolchain-sqlite](https://github.com/swiftlang/swift-toolchain-sqlite) with `condition: .when(platforms: [.android, .linux, .windows])` and imports it with `#if canImport(SQLite3) import SQLite3 #else import SwiftToolchainCSQLite #endif`; Apple builds keep using the system SQLite.
- Gate Apple-only APIs/constants instead of deleting them, e.g. `kCFBundleIdentifierKey`/`kCFBundleVersionKey` in `Sources/Apollo/Internal Utilities/Bundle+Helpers.swift`. Use `#if canImport(...)` / `#if os(Android)` so Apple platforms keep building.
- Never redeclare Foundation members that Android's `Foundation` already provides. `Bundle.bundleIdentifier` exists there; declaring it in an extension makes the Skip bridge's `AndroidBundle` subclass vtable deserialize ambiguously ("result is ambiguous") and crashes `swift-frontend` in any module that imports Apollo. Gate such members with `#if !os(Android)`; see `Bundle+Helpers.swift`.
- The fork never sets `User-Agent`. On Android, corelibs' `URLSession` supplies its own; a `CFNetwork/... Darwin/...` UA captured while app testing came from an iOS-simulator request, not the Android port.

## Known open items

- One app-side report (2026-09-12) saw two WebSocket connections for a single subscription on a physical Android 12 device. The same flow through `WebSocketTransport` on an emulator opened exactly one connection, so check for a second transport instance before changing transport code. Auto-reconnect after a dropped connection is unverified.

## Current Android status

All five targets (`ApolloAPI`, `Apollo`, `ApolloSQLite`, `ApolloWebSocket`, `ApolloTestSupport`) build for Android, and the full test suite passes on-device with `skip android test`. The port added conditional `FoundationNetworking` imports, a `URLSessionDataTask`/delegate replacement for the Darwin `AsyncBytes` networking path, `JSONValueConversion` to normalize Foundation JSON values that corelibs returns/bridges differently, and the `swift-toolchain-sqlite` dependency for SQLite. `URLSessionWebSocketTask` was verified live on Android, and the SQLite cache was verified at runtime (temporary probe; the test app was reverted to an in-memory cache afterwards). A real Skip Fuse app (`../apollo-test`, Apollo + generated models + SkipFuseUI) also compiles, installs and launches on a connected Android 12 device; the `swift-frontend` SIL vtable crash that previously blocked app compilation was the `Bundle.bundleIdentifier` collision described above. Re-run `skip android build`/`skip android test` rather than trusting this snapshot.

## Versioning

- `ApolloClientVersion` in `Sources/Apollo/Constants.swift` is the source of truth and is kept in sync with the bundled CLI tarball; `scripts/cli-version-check.sh` verifies they match. Don't bump it without a matching release.
- Releases: push tag `vX.Y.Z` → `.github/workflows/release.yml` creates a GitHub release with body from `changelogs/vX.Y.Z.md`. Add the changelog file first, then `git tag vX.Y.Z && git push origin vX.Y.Z`. Fork tags use a `v` prefix; upstream tags are bare numbers.
