import Foundation
import XCTest

@_spi(Unsafe) import ApolloAPI

/// Platform-neutral tests for the `DataDict` scalar subscript.
///
/// A GraphQL `null` scalar is stored as `NSNull` (see `DataDictMapper.acceptNullValue`), and
/// nullable scalar fields are read back through `subscript<T: AnyScalarType>(_:) -> T`. On Darwin
/// the runtime casts `AnyHashable(NSNull())` to `nil` for an optional target, but
/// swift-corelibs-foundation on Android has no such special case, so the force-cast used to trap —
/// crashing the app whenever a nullable field (Pronouns, group avatarUrl, …) came back `null`.
/// These tests pin the normalized behavior on both platforms and run in Android CI via
/// `skip android test`.
final class DataDictScalarTests: XCTestCase {

  func testNullScalar_readsAsNil_forOptionalFields() {
    let data = DataDict(data: ["pronouns": NSNull()], fulfilledFragments: [])
    XCTAssertNil(data["pronouns"] as String?)
  }

  func testMissingScalar_readsAsNil_forOptionalFields() {
    let data = DataDict(data: [:], fulfilledFragments: [])
    XCTAssertNil(data["pronouns"] as String?)
  }

  func testPresentScalars_areReadBack() {
    let data = DataDict(
      data: ["name": "Ada", "count": 3, "flag": true],
      fulfilledFragments: []
    )
    XCTAssertEqual(data["name"] as String?, "Ada")
    XCTAssertEqual(data["count"] as Int?, 3)
    XCTAssertEqual(data["flag"] as Bool?, true)
  }
}
