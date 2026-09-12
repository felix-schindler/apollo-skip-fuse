# Tests

Platform-neutral tests for this fork. `swift test` runs them on macOS; `skip android test` runs them on a connected device/emulator:

- `ApolloAPITests` — JSON value conversion/normalization, which behaves differently on corelibs Foundation.
- `ApolloSQLiteTests` — SQLite cache backend.
- `ApolloWebSocketTests` — WebSocket transport.

The full upstream Apollo iOS test suite lives in [apollo-ios-dev](https://github.com/apollographql/apollo-ios-dev/tree/main/Tests) and cannot be run from this repo.
