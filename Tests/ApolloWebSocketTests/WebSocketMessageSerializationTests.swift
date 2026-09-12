import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

@_spi(Internal) import ApolloAPI
@testable import ApolloWebSocket

/// Tests for the `graphql-transport-ws` message serialization and deserialization.
final class WebSocketMessageSerializationTests: XCTestCase {

  // MARK: - Helpers

  private func messageData(_ message: URLSessionWebSocketTask.Message) throws -> Data {
    guard case .string(let string) = message else {
      throw NSError(domain: "WebSocketMessageSerializationTests", code: 1)
    }
    return Data(string.utf8)
  }

  private func jsonObject(_ message: URLSessionWebSocketTask.Message) throws -> [String: Any] {
    let data = try messageData(message)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  // MARK: - Serialization

  func testConnectionInit_withNilPayload_serializesTypeOnly() throws {
    let message = try WebSocketTransport.Message.Outgoing.connectionInit(payload: nil).toWebSocketMessage()
    let json = try jsonObject(message)

    XCTAssertEqual(json["type"] as? String, "connection_init")
    XCTAssertNil(json["payload"])
    XCTAssertEqual(json.count, 1)
  }

  func testConnectionInit_withNestedPayload_serializesNestedValues() throws {
    let message = try WebSocketTransport.Message.Outgoing.connectionInit(payload: [
      "auth": ["user": "admin", "pass": "secret"] as JSONEncodableDictionary
    ]).toWebSocketMessage()
    let json = try jsonObject(message)

    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    let auth = try XCTUnwrap(payload["auth"] as? [String: Any])
    XCTAssertEqual(auth["user"] as? String, "admin")
    XCTAssertEqual(auth["pass"] as? String, "secret")
  }

  func testSubscribe_withVariablesAndExtensions_serializesAllFields() throws {
    let message = try WebSocketTransport.Message.Outgoing.subscribe(id: "42", payload: [
      "operationName": "OnReview",
      "query": "subscription OnReview($episode: Episode!) { onReview(episode: $episode) { stars } }",
      "variables": ["episode": "JEDI"] as JSONEncodableDictionary,
      "extensions": ["version": 1] as JSONEncodableDictionary,
    ]).toWebSocketMessage()
    let json = try jsonObject(message)

    XCTAssertEqual(json["type"] as? String, "subscribe")
    XCTAssertEqual(json["id"] as? String, "42")

    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    XCTAssertEqual(payload["operationName"] as? String, "OnReview")
    let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
    XCTAssertEqual(variables["episode"] as? String, "JEDI")
    let extensions = try XCTUnwrap(payload["extensions"] as? [String: Any])
    XCTAssertEqual((extensions["version"] as? NSNumber)?.intValue, 1)
  }

  func testComplete_serializesTypeAndId() throws {
    let message = try WebSocketTransport.Message.Outgoing.complete(id: "1").toWebSocketMessage()
    let json = try jsonObject(message)

    XCTAssertEqual(json["type"] as? String, "complete")
    XCTAssertEqual(json["id"] as? String, "1")
    XCTAssertEqual(json.count, 2)
  }

  func testAllOutgoingMessages_produceValidJSONStrings() throws {
    let messages: [WebSocketTransport.Message.Outgoing] = [
      .connectionInit(payload: ["key": "value"]),
      .ping(payload: ["key": "value"]),
      .pong(payload: ["key": "value"]),
      .subscribe(id: "1", payload: [
        "operationName": "Op",
        "query": "subscription Op { onEvent { id } }",
        "variables": ["a": "b"] as JSONEncodableDictionary,
      ]),
      .complete(id: "1"),
    ]

    for outgoing in messages {
      let message = try outgoing.toWebSocketMessage()
      _ = try jsonObject(message)
    }
  }

  // MARK: - Deserialization

  func testConnectionAck_deserializesWithPayload() throws {
    let incoming = try WebSocketTransport.Message.Incoming.from(
      .string(#"{"type":"connection_ack","payload":{"version":"1.0"}}"#)
    )

    guard case .connectionAck(let payload) = incoming else {
      return XCTFail("Expected .connectionAck, got \(incoming)")
    }
    XCTAssertEqual(payload?["version"] as? String, "1.0")
  }

  func testNext_deserializesWithStringIdAndNestedData() throws {
    let incoming = try WebSocketTransport.Message.Incoming.from(
      .string(#"{"type":"next","id":"1","payload":{"data":{"hero":{"name":"Luke"}}}}"#)
    )

    guard case .next(let id, let payload) = incoming else {
      return XCTFail("Expected .next, got \(incoming)")
    }
    XCTAssertEqual(id, "1")

    let data = try XCTUnwrap(JSONValueConversion.jsonObject(from: payload["data"]))
    let hero = try XCTUnwrap(JSONValueConversion.jsonObject(from: data["hero"]))
    XCTAssertEqual(hero["name"] as? String, "Luke")
  }

  func testNext_deserializesWithIntId() throws {
    let incoming = try WebSocketTransport.Message.Incoming.from(
      .string(#"{"type":"next","id":5,"payload":{"data":{"count":42}}}"#)
    )

    guard case .next(let id, let payload) = incoming else {
      return XCTFail("Expected .next, got \(incoming)")
    }
    XCTAssertEqual(id, "5")

    let data = try XCTUnwrap(JSONValueConversion.jsonObject(from: payload["data"]))
    XCTAssertEqual((data["count"] as? NSNumber)?.intValue, 42)
  }

  func testError_deserializesMultipleErrors() throws {
    let incoming = try WebSocketTransport.Message.Incoming.from(
      .string(#"{"type":"error","id":"3","payload":[{"message":"Error one"},{"message":"Error two"}]}"#)
    )

    guard case .error(let id, let errors) = incoming else {
      return XCTFail("Expected .error, got \(incoming)")
    }
    XCTAssertEqual(id, "3")
    XCTAssertEqual(errors.count, 2)
    XCTAssertEqual(errors[0].message, "Error one")
    XCTAssertEqual(errors[1].message, "Error two")
  }

  func testComplete_deserializesWithIntId() throws {
    let incoming = try WebSocketTransport.Message.Incoming.from(
      .string(#"{"type":"complete","id":7}"#)
    )

    guard case .complete(let id) = incoming else {
      return XCTFail("Expected .complete, got \(incoming)")
    }
    XCTAssertEqual(id, "7")
  }

  func testDeserialization_fromDataMessage() throws {
    let data = Data(#"{"type":"complete","id":"1"}"#.utf8)
    let incoming = try WebSocketTransport.Message.Incoming.from(.data(data))

    guard case .complete(let id) = incoming else {
      return XCTFail("Expected .complete, got \(incoming)")
    }
    XCTAssertEqual(id, "1")
  }

  func testDeserialization_unknownType_throws() {
    XCTAssertThrowsError(
      try WebSocketTransport.Message.Incoming.from(.string(#"{"type":"unknown_message"}"#))
    ) { error in
      guard case WebSocketTransport.Error.unrecognizedMessage = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testDeserialization_invalidJSON_throws() {
    XCTAssertThrowsError(
      try WebSocketTransport.Message.Incoming.from(.string("not valid json"))
    )
  }
}
