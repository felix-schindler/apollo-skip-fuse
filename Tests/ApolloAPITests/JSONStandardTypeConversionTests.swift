import Foundation
import XCTest

@_spi(Internal) import ApolloAPI

/// Platform-neutral tests for the JSON and scalar conversions in `ApolloAPI`.
///
/// These run on macOS with `swift test` and on Android with `skip android test`. The conversions are the part of
/// `ApolloAPI` that depends on Foundation's `NSNumber`/`NSNull`/`JSONSerialization` behavior, which differs between
/// Darwin and swift-corelibs-foundation, so they are the real risk for the Android port.
final class JSONStandardTypeConversionTests: XCTestCase {

  // MARK: - Decoding

  func testIntDecoding_fromNumber() throws {
    XCTAssertEqual(try Int(_jsonValue: NSNumber(value: 42)), 42)
    XCTAssertEqual(try Int(_jsonValue: NSNumber(value: -7)), -7)
  }

  func testInt32Decoding_fromNumber() throws {
    XCTAssertEqual(try Int32(_jsonValue: NSNumber(value: 42)), 42)
  }

  func testFloatDecoding_fromNumber() throws {
    XCTAssertEqual(try Float(_jsonValue: NSNumber(value: 1.5)), 1.5)
  }

  func testDoubleDecoding_fromNumber() throws {
    XCTAssertEqual(try Double(_jsonValue: NSNumber(value: 1.25)), 1.25)
  }

  func testBoolDecoding_fromNumber() throws {
    XCTAssertEqual(try Bool(_jsonValue: NSNumber(value: true)), true)
    XCTAssertEqual(try Bool(_jsonValue: NSNumber(value: false)), false)
  }

  func testBoolDecoding_fromJSONSerialization() throws {
    let data = Data(#"[true,false]"#.utf8)
    let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])

    let decoded = try values.map { try Bool(_jsonValue: $0 as! JSONValue) }
    XCTAssertEqual(decoded, [true, false])
  }

  func testStringDecoding_fromNumbers() throws {
    XCTAssertEqual(try String(_jsonValue: Int(1)), "1")
    XCTAssertEqual(try String(_jsonValue: Int32(2)), "2")
    XCTAssertEqual(try String(_jsonValue: Int64(3)), "3")
    XCTAssertEqual(try String(_jsonValue: Double(1.5)), "1.5")
  }

  func testOptionalDecoding_fromNSNullAndValue() throws {
    let null: Int? = try Optional<Int>(jsonValue: NSNull())
    XCTAssertNil(null)

    let value: Int? = try Optional<Int>(jsonValue: NSNumber(value: 8))
    XCTAssertEqual(value, 8)
  }

  // MARK: - Encoding

  func testOptionalEncoding_noneIsNSNull() {
    XCTAssertTrue(Optional<Int>.none._jsonValue is NSNull)
  }

  func testJSONObjectEncoding_roundTripsThroughJSONSerialization() throws {
    let object: JSONObject = [
      "int": Int(1)._jsonValue,
      "int32": Int32(2)._jsonValue,
      "float": Float(3.5)._jsonValue,
      "double": Double(4.25)._jsonValue,
      "boolTrue": true._jsonValue,
      "boolFalse": false._jsonValue,
      "string": "text"._jsonValue,
      "null": Optional<Int>.none._jsonValue,
      "array": [Int(1), Int(2)]._jsonValue,
      "nested": ["key": "value"]._jsonValue,
    ]

    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual((decoded["int"] as? NSNumber)?.intValue, 1)
    XCTAssertEqual((decoded["int32"] as? NSNumber)?.int32Value, 2)
    XCTAssertEqual((decoded["float"] as? NSNumber)?.floatValue, 3.5)
    XCTAssertEqual((decoded["double"] as? NSNumber)?.doubleValue, 4.25)
    XCTAssertEqual(decoded["boolTrue"] as? Bool, true)
    XCTAssertEqual(decoded["boolFalse"] as? Bool, false)
    XCTAssertEqual(decoded["string"] as? String, "text")
    XCTAssertTrue(decoded["null"] is NSNull)
    XCTAssertEqual((decoded["array"] as? [Any])?.count, 2)
    XCTAssertEqual((decoded["nested"] as? [String: Any])?["key"] as? String, "value")
  }

  func testJSONObjectDecoding_fromJSONSerialization() throws {
    let data = Data(#"""
      {
        "a_bool": true,
        "an_int": 8,
        "a_double": 23.1,
        "a_string": "LOL wat",
        "a_null": null,
        "an_array": ["one", "two"],
        "a_dict": { "nested": 1 }
      }
      """#.utf8)

    let deserialized = try JSONSerialization.jsonObject(with: data, options: [])
    let value = try JSONValueConversion.convert(deserialized)
    let decoded = try JSONObject(_jsonValue: value)

    XCTAssertEqual(decoded["a_bool"] as? Bool, true)
    XCTAssertEqual((decoded["an_int"] as? NSNumber)?.intValue, 8)
    XCTAssertEqual((decoded["a_double"] as? NSNumber)?.doubleValue, 23.1)
    XCTAssertEqual(decoded["a_string"] as? String, "LOL wat")
    XCTAssertTrue(decoded["a_null"] is NSNull)
    XCTAssertEqual((decoded["an_array"] as? [Any])?.count, 2)
    XCTAssertEqual(((decoded["a_dict"] as? JSONObject)?["nested"] as? NSNumber)?.intValue, 1)
  }

  func testJSONObjectDecoding_fromConcreteDictionary() throws {
    let dictionary: [String: NSNumber] = ["a": NSNumber(value: 1), "b": NSNumber(value: 2)]
    let decoded = try JSONObject(_jsonValue: dictionary)

    XCTAssertEqual(decoded.count, 2)
    XCTAssertEqual((decoded["a"] as? NSNumber)?.intValue, 1)
    XCTAssertEqual((decoded["b"] as? NSNumber)?.intValue, 2)
  }

  func testNSNullEncoding_doesNotCrash() throws {
    let object: JSONObject = ["aWeirdNull": NSNull()]
    let data = try JSONSerialization.data(withJSONObject: object)
    XCTAssertEqual(try XCTUnwrap(String(data: data, encoding: .utf8)), #"{"aWeirdNull":null}"#)
  }

  // MARK: - JSONValueConversion

  func testJSONValueConversion_handlesNestedCollections() throws {
    let data = Data(#"{"array":[1,"two",null,{"nested":true}],"object":{"key":[1.5,false]}}"#.utf8)
    let deserialized = try JSONSerialization.jsonObject(with: data)
    let value = try JSONValueConversion.convert(deserialized)
    let object = try JSONObject(_jsonValue: value)

    let array = try XCTUnwrap(JSONValueConversion.jsonArray(from: object["array"]))
    XCTAssertEqual((array[0] as? NSNumber)?.intValue, 1)
    XCTAssertEqual(array[1] as? String, "two")
    XCTAssertTrue(array[2] is NSNull)
    let nested = try XCTUnwrap(JSONValueConversion.jsonObject(from: array[3]))
    XCTAssertEqual(nested["nested"] as? Bool, true)

    let child = try XCTUnwrap(JSONValueConversion.jsonObject(from: object["object"]))
    let key = try XCTUnwrap(JSONValueConversion.jsonArray(from: child["key"]))
    XCTAssertEqual((key[0] as? NSNumber)?.doubleValue, 1.5)
    XCTAssertEqual(key[1] as? Bool, false)
  }

  func testJSONValueConversion_topLevelArray() throws {
    let data = Data(#"[1,"two",true,null]"#.utf8)
    let deserialized = try JSONSerialization.jsonObject(with: data)
    let value = try JSONValueConversion.convert(deserialized)
    let array = try XCTUnwrap(value as? [JSONValue])

    XCTAssertEqual((array[0] as? NSNumber)?.intValue, 1)
    XCTAssertEqual(array[1] as? String, "two")
    XCTAssertEqual(array[2] as? Bool, true)
    XCTAssertTrue(array[3] is NSNull)
  }
}
