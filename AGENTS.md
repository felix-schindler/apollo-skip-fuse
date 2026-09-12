# AGENTS.md

## What this repo is

- Fork of [apollographql/apollo-ios](https://github.com/apollographql/apollo-ios) at v2.4.0 (runtime package only).
- Fork goal: make this package build and run on Android via [Skip Fuse](https://skip.dev/docs/modes/), without breaking the Apple platforms.
- No code generation, no CLI sources, no tests here. The CLI is a prebuilt binary: `make` unpacks `CLI/apollo-ios-cli.tar.gz`; the `InstallCLI` command plugin downloads it on demand. Upstream tests live in [apollo-ios-dev](https://github.com/apollographql/apollo-ios-dev) — `Tests/` only contains a pointer README.
- Targets and dependency direction (all targets are Swift 6 language mode):
  - `ApolloAPI` — protocols/types consumed by generated models; depends on nothing.
  - `Apollo` — client, request chain/interceptors, normalized cache; depends on `ApolloAPI`.
  - `ApolloSQLite`, `ApolloWebSocket` — cache and transport backends; depend on `Apollo`.
  - `ApolloTestSupport` — mocks for generated models; depends on `Apollo` + `ApolloAPI`.
- The public API is consumed by user-generated code from the standard Apollo CLI; avoid source-breaking changes.

## Build and verify

- Apple platforms: `swift build` from the repo root (fast; builds all targets).
- Android: `skip android build` (Skip CLI 1.9.8 is installed). It cross-compiles `aarch64-unknown-linux-android28` with the Swift Android SDK and passes `-DSKIP_BRIDGE -DTARGET_OS_ANDROID`.
- Do not run `swift build --swift-sdk ...` with the default `swift` in `PATH`: it uses Xcode's toolchain and fails with the misleading `compiled module was created by an older version of the compiler`. `skip android build` selects the matching Swiftly 6.3.3 toolchain.
- Minimum verification for every change: `swift build` **and** `skip android build`.
- There is no test target, so `swift test` runs nothing. For behavior changes add a platform-neutral test target that runs with `swift test` on macOS and `skip android test` on a connected device/emulator. The upstream Apollo test suite cannot be run from this repo.
- `skip doctor` diagnoses a broken Skip environment. The only CI here is issue triage/security; `skiptools/swift-android-action@v2` is the Skip-maintained action if Android CI is added.

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
- `URLSessionWebSocketTask` compiles on Android once `FoundationNetworking` is imported; runtime support is not yet verified.
- `import SQLite3` is not available from the Android Swift SDK (verified). `ApolloSQLite` needs a system-library/module-map shim for Android's libsqlite3, or a [SkipSQL](https://skip.dev/docs/modules/skip-sql/)-based backend.
- Gate Apple-only APIs/constants instead of deleting them, e.g. `kCFBundleIdentifierKey`/`kCFBundleVersionKey` in `Sources/Apollo/Internal Utilities/Bundle+Helpers.swift`. Use `#if canImport(...)` / `#if os(Android)` so Apple platforms keep building.

## Current Android status

As of this port: `ApolloAPI` **and** `Apollo` build for Android (`skip android build --target Apollo`). The `Apollo` port added conditional `FoundationNetworking` imports plus a `URLSessionDataTask`/delegate replacement for the Darwin `AsyncBytes` networking path. Remaining: `ApolloWebSocket` (needs the same `FoundationNetworking` imports, then runtime verification) and `ApolloSQLite` (needs a SQLite3 solution). Re-run `skip android build` rather than trusting this snapshot.

## Versioning

- `ApolloClientVersion` in `Sources/Apollo/Constants.swift` is the source of truth; `scripts/get-version.sh` and the CLI download script derive from it. Don't bump it without a matching release, or `InstallCLI` will try to download a nonexistent tarball.
- Releases: push tag `vX.Y.Z` → `.github/workflows/release.yml` creates a GitHub release with body from `changelogs/vX.Y.Z.md`. Add the changelog file first, then `git tag vX.Y.Z && git push origin vX.Y.Z`. Fork tags use a `v` prefix; upstream tags are bare numbers.
