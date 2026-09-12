import Foundation

/// Converts values returned by `JSONSerialization` into ``JSONValue``s, and normalizes JSON object/list values that
/// may have been bridged to `NSDictionary`/`NSArray`.
///
/// On Darwin, `JSONSerialization` returns `NSDictionary`/`NSArray`, which conform to `Hashable` and `Sendable`.
/// On other platforms (such as Android), it returns Swift `[String: Any]`/`[Any]` values instead. Those cannot be
/// cast directly to ``JSONValue`` because `Any` is neither `Hashable` nor `Sendable`, so this utility recursively
/// converts them into ``JSONObject``s and `[JSONValue]`s.
@_spi(Internal)
public enum JSONValueConversion {

  /// Converts a value returned by `JSONSerialization` into a ``JSONValue``.
  ///
  /// - Parameter value: A JSON value returned by `JSONSerialization`.
  /// - Throws: ``JSONDecodingError/wrongType`` if the value is not a valid JSON type.
  public static func convert(_ value: Any) throws -> JSONValue {
    switch value {
    case is NSNull:
      return NSNull()

    case let dictionary as [String: Any]:
      return try makeObject(from: dictionary) as JSONValue

    case let dictionary as [AnyHashable: Any]:
      var result = JSONObject()
      result.reserveCapacity(dictionary.count)
      for (key, value) in dictionary {
        guard let key = key as? String else { throw JSONDecodingError.wrongType }
        result[key] = try convert(value)
      }
      return result as JSONValue

    case let array as [Any]:
      return try array.map { try convert($0) } as JSONValue

    case let number as NSNumber:
      return number

    case let string as String:
      return string

    case let bool as Bool:
      return bool

    case let int as Int:
      return int

    case let int32 as Int32:
      return int32

    case let int64 as Int64:
      return int64

    case let float as Float:
      return float

    case let double as Double:
      return double

    default:
      throw JSONDecodingError.wrongType
    }
  }

  /// Returns the ``JSONObject`` represented by `value`, if it is a JSON object.
  ///
  /// Nested collections are normalized here because code compiled for non-Darwin platforms bridges dictionaries
  /// and arrays with existential values to `NSDictionary`/`NSArray` when they are boxed in a ``JSONValue``. Those
  /// bridged values cannot always be cast back to ``JSONObject``/`[JSONValue]` directly.
  public static func jsonObject(from value: JSONValue?) -> JSONObject? {
    guard let value else { return nil }

    if let object = value as? JSONObject {
      return object
    }

    guard let dictionary = value as? [String: Any] else { return nil }
    return try? makeObject(from: dictionary)
  }

  /// Returns the `[JSONValue]` represented by `value`, if it is a JSON list.
  public static func jsonArray(from value: JSONValue?) -> [JSONValue]? {
    guard let value else { return nil }

    if let array = value as? [JSONValue] {
      return array
    }

    guard let array = value as? [Any] else { return nil }
    return try? array.map { try convert($0) }
  }

  /// Returns the `[JSONObject]` represented by `value`, if it is a JSON list of objects.
  public static func jsonObjectsArray(from value: JSONValue?) -> [JSONObject]? {
    guard let array = jsonArray(from: value) else { return nil }

    let objects = array.compactMap { jsonObject(from: $0) }
    guard objects.count == array.count else { return nil }
    return objects
  }

  private static func makeObject(from dictionary: [String: Any]) throws -> JSONObject {
    var result = JSONObject()
    result.reserveCapacity(dictionary.count)
    for (key, value) in dictionary {
      result[key] = try convert(value)
    }
    return result
  }
}
