import Foundation
import XCTest

@_spi(Internal) import Apollo
@_spi(Internal) import ApolloAPI

/// Tests `JSONSerializationFormat`, the entry point that parses GraphQL network responses into `JSONObject`s.
///
/// This exercises the Android-specific failure path where `JSONSerialization` returns Swift `[String: Any]` and
/// `[Any]` values rather than `NSDictionary`/`NSArray`.
final class JSONSerializationFormatTests: XCTestCase {

  func testDeserialize_object() throws {
    let data = Data(#"{"data":{"hero":{"name":"Luke"}},"errors":null}"#.utf8)
    let object: JSONObject = try JSONSerializationFormat.deserialize(data: data)

    let dataObject = try XCTUnwrap(JSONValueConversion.jsonObject(from: object["data"]))
    let hero = try XCTUnwrap(JSONValueConversion.jsonObject(from: dataObject["hero"]))
    XCTAssertEqual(hero["name"] as? String, "Luke")
    XCTAssertTrue(object["errors"] is NSNull)
  }

  func testDeserialize_array() throws {
    let data = Data(#"[{"data":1},{"data":2}]"#.utf8)
    let array: [JSONValue] = try JSONSerializationFormat.deserialize(data: data)

    XCTAssertEqual(array.count, 2)
    let first = try XCTUnwrap(JSONValueConversion.jsonObject(from: array[0]))
    XCTAssertEqual((first["data"] as? NSNumber)?.intValue, 1)
  }

  func testDeserialize_nestedIncrementalResponse() throws {
    let data = Data(#"{"incremental":[{"path":["hero"],"data":{"name":"Leia"}}],"hasNext":true}"#.utf8)
    let object: JSONObject = try JSONSerializationFormat.deserialize(data: data)

    let incremental = try XCTUnwrap(JSONValueConversion.jsonArray(from: object["incremental"]))
    let first = try XCTUnwrap(JSONValueConversion.jsonObject(from: incremental[0]))
    let path = try XCTUnwrap(JSONValueConversion.jsonArray(from: first["path"]))
    XCTAssertEqual(path[0] as? String, "hero")
    XCTAssertEqual(object["hasNext"] as? Bool, true)
  }
}
