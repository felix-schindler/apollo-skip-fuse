import Foundation
import XCTest

@testable import ApolloWebSocket

/// Tests for `OperationMessageIdCreator` implementations.
final class OperationMessageIdCreatorTests: XCTestCase {

  func testSequencedCreator_defaultStartsAtOne() {
    var creator = ApolloSequencedOperationMessageIdCreator()

    XCTAssertEqual(creator.requestId(), "1")
    XCTAssertEqual(creator.requestId(), "2")
    XCTAssertEqual(creator.requestId(), "3")
  }

  func testSequencedCreator_customStartNumber() {
    var creator = ApolloSequencedOperationMessageIdCreator(startAt: 5)

    XCTAssertEqual(creator.requestId(), "5")
    XCTAssertEqual(creator.requestId(), "6")
    XCTAssertEqual(creator.requestId(), "7")
  }

  func testSequencedCreator_zeroAndLargeStartNumbers() {
    var zero = ApolloSequencedOperationMessageIdCreator(startAt: 0)
    XCTAssertEqual(zero.requestId(), "0")
    XCTAssertEqual(zero.requestId(), "1")

    var large = ApolloSequencedOperationMessageIdCreator(startAt: 999_999)
    XCTAssertEqual(large.requestId(), "999999")
    XCTAssertEqual(large.requestId(), "1000000")
  }

  func testCustomCreator_returnsExpectedIds() {
    struct FixedIdCreator: OperationMessageIdCreator {
      mutating func requestId() -> String {
        return "custom-fixed-id"
      }
    }

    var creator = FixedIdCreator()
    XCTAssertEqual(creator.requestId(), "custom-fixed-id")
    XCTAssertEqual(creator.requestId(), "custom-fixed-id")
  }

  func testCustomCreator_uuidBased() {
    struct UUIDIdCreator: OperationMessageIdCreator {
      mutating func requestId() -> String {
        return UUID().uuidString
      }
    }

    var creator = UUIDIdCreator()
    let id1 = creator.requestId()
    let id2 = creator.requestId()

    XCTAssertNotEqual(id1, id2)
    XCTAssertEqual(id1.count, 36)
    XCTAssertEqual(id2.count, 36)
  }
}
