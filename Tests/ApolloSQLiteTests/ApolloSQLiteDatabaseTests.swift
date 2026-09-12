import Foundation
import XCTest

@_spi(Execution) import Apollo
@_spi(Testing) import ApolloSQLite

final class ApolloSQLiteDatabaseTests: XCTestCase {

  private var databaseURL: URL!

  override func setUpWithError() throws {
    databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("apollo-sqlite-tests-\(UUID().uuidString).sqlite")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: databaseURL)
  }

  private func makeDatabase() throws -> ApolloSQLiteDatabase {
    let database = try ApolloSQLiteDatabase(fileURL: databaseURL)
    try database.createRecordsTableIfNeeded()
    return database
  }

  // MARK: - SQLiteDatabase

  func testAddOrUpdateAndSelectRawRows() throws {
    let database = try makeDatabase()
    try database.addOrUpdate(records: [
      (cacheKey: "QUERY_ROOT.hero", recordString: #"{"__typename":"Human","name":"Luke"}"#),
      (cacheKey: "QUERY_ROOT.hero.friends.0", recordString: #"{"__typename":"Human","name":"Han"}"#),
    ])

    let rows = try database.selectRawRows(forKeys: ["QUERY_ROOT.hero", "QUERY_ROOT.hero.friends.0"])
    XCTAssertEqual(rows.count, 2)

    let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.cacheKey, $0.storedInfo) })
    XCTAssertEqual(byKey["QUERY_ROOT.hero"], #"{"__typename":"Human","name":"Luke"}"#)
    XCTAssertEqual(byKey["QUERY_ROOT.hero.friends.0"], #"{"__typename":"Human","name":"Han"}"#)
  }

  func testAddOrUpdate_replacesExistingRecord() throws {
    let database = try makeDatabase()
    try database.addOrUpdate(records: [(cacheKey: "key", recordString: #"{"value":1}"#)])
    try database.addOrUpdate(records: [(cacheKey: "key", recordString: #"{"value":2}"#)])

    let rows = try database.selectRawRows(forKeys: ["key"])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.storedInfo, #"{"value":2}"#)
  }

  func testDeleteRecord() throws {
    let database = try makeDatabase()
    try database.addOrUpdate(records: [
      (cacheKey: "a", recordString: "{}"),
      (cacheKey: "b", recordString: "{}"),
    ])

    try database.deleteRecord(for: "a")

    XCTAssertTrue(try database.selectRawRows(forKeys: ["a"]).isEmpty)
    XCTAssertEqual(try database.selectRawRows(forKeys: ["b"]).count, 1)
  }

  func testDeleteRecordsMatchingPattern() throws {
    let database = try makeDatabase()
    try database.addOrUpdate(records: [
      (cacheKey: "QUERY_ROOT.a", recordString: "{}"),
      (cacheKey: "QUERY_ROOT.b", recordString: "{}"),
      (cacheKey: "MUTATION_ROOT.a", recordString: "{}"),
    ])

    try database.deleteRecords(matching: "QUERY_ROOT")

    let rows = try database.selectRawRows(forKeys: ["QUERY_ROOT.a", "QUERY_ROOT.b", "MUTATION_ROOT.a"])
    XCTAssertEqual(rows.map(\.cacheKey), ["MUTATION_ROOT.a"])
  }

  func testClearDatabase_withVacuum() throws {
    let database = try makeDatabase()
    try database.addOrUpdate(records: [
      (cacheKey: "a", recordString: "{}"),
      (cacheKey: "b", recordString: "{}"),
    ])

    try database.clearDatabase(shouldVacuumOnClear: true)

    XCTAssertTrue(try database.selectRawRows(forKeys: ["a", "b"]).isEmpty)
  }

  func testRecordsPersistAcrossConnections() throws {
    do {
      let database = try makeDatabase()
      try database.addOrUpdate(records: [(cacheKey: "key", recordString: #"{"n":1}"#)])
    }

    let reopened = try makeDatabase()
    let rows = try reopened.selectRawRows(forKeys: ["key"])
    XCTAssertEqual(rows.first?.storedInfo, #"{"n":1}"#)
  }

  // MARK: - SQLiteNormalizedCache

  func testNormalizedCache_mergeLoadRemoveAndClear() throws {
    let cache = try SQLiteNormalizedCache(fileURL: databaseURL)

    let records = RecordSet(records: [
      Record(key: "QUERY_ROOT", ["name": "Luke"]),
      Record(key: "QUERY_ROOT.hero", ["__typename": "Human"]),
    ])
    _ = try cache.merge(records: records)

    let loaded = try cache.loadRecords(forKeys: ["QUERY_ROOT.hero"])
    XCTAssertEqual(loaded["QUERY_ROOT.hero"]?["__typename"] as? String, "Human")

    try cache.removeRecord(for: "QUERY_ROOT.hero")
    XCTAssertNil(try cache.loadRecords(forKeys: ["QUERY_ROOT.hero"])["QUERY_ROOT.hero"])

    try cache.clear()
    XCTAssertTrue(try cache.loadRecords(forKeys: ["QUERY_ROOT"]).isEmpty)
  }

  func testNormalizedCache_roundTripsCacheReferences() throws {
    let cache = try SQLiteNormalizedCache(fileURL: databaseURL)

    let records = RecordSet(records: [
      Record(key: "QUERY_ROOT.hero", [
        "__typename": "Human",
        "friend": CacheReference("Human:1000"),
        "friends": [CacheReference("Human:1001"), CacheReference("Human:1002")] as [CacheReference],
      ]),
    ])
    _ = try cache.merge(records: records)

    let loaded = try XCTUnwrap(try cache.loadRecords(forKeys: ["QUERY_ROOT.hero"])["QUERY_ROOT.hero"])
    XCTAssertEqual(loaded["friend"] as? CacheReference, CacheReference("Human:1000"))
    XCTAssertEqual(loaded["friends"] as? [CacheReference], [
      CacheReference("Human:1001"),
      CacheReference("Human:1002"),
    ])
  }
}
