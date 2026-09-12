import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
import ApolloWebSocket

/// End-to-end tests for ``WebSocketTransport`` against a mock server that speaks the
/// `graphql-transport-ws` protocol, exercising the full stack: connection handshake, message
/// serialization, response parsing and cache writing.
final class WebSocketTransportTests: XCTestCase {

  // MARK: - Mock schema

  private enum TestSchemaMetadata: SchemaMetadata {
    static let configuration: any SchemaConfiguration.Type = TestSchemaConfiguration.self

    static func objectType(forTypename __typename: String) -> Object? {
      Object(typename: __typename, implementedInterfaces: [])
    }
  }

  private enum TestSchemaConfiguration: SchemaConfiguration {
    static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? { nil }
  }

  @dynamicMemberLookup
  private class MockSelectionSet: RootSelectionSet, Hashable, @unchecked Sendable {
    typealias Schema = TestSchemaMetadata
    typealias Fragments = NoFragments

    class var __selections: [Selection] { [] }
    class var __parentType: any ParentType { Object(typename: "Mock", implementedInterfaces: []) }
    class var __fulfilledFragments: [any SelectionSet.Type] { [] }

    var __data: DataDict = .init(data: [:], fulfilledFragments: [])

    required init(_dataDict: DataDict) {
      __data = _dataDict
    }

    subscript<T: AnyScalarType & Hashable>(dynamicMember key: String) -> T? {
      __data[key]
    }
  }

  private final class NumberSubscription: GraphQLSubscription, @unchecked Sendable {
    typealias Data = NumberData

    static var operationName: String { "NumberSubscription" }
    static var operationDocument: OperationDocument {
      .init(definition: .init("subscription NumberSubscription { number }"))
    }

    final class NumberData: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("number", Int.self)] }

      var number: Int { __data["number"] }
    }
  }

  // MARK: - Mock graphql-transport-ws server

  private enum SubscribeResponse {
    case success(number: Int)
    case error(message: String)
  }

  private final class MockGraphQLWSServerTask: WebSocketTask, @unchecked Sendable {
    private let lock = NSLock()
    private let subscribeResponse: SubscribeResponse

    private let continuation: AsyncStream<URLSessionWebSocketTask.Message>.Continuation
    private var iterator: AsyncStream<URLSessionWebSocketTask.Message>.Iterator

    private var _sentMessageTypes: [String] = []
    private var _cancelCall: (code: URLSessionWebSocketTask.CloseCode, reason: Data?)?

    init(subscribeResponse: SubscribeResponse = .success(number: 42)) {
      let (stream, continuation) = AsyncStream<URLSessionWebSocketTask.Message>.makeStream()
      self.continuation = continuation
      self.iterator = stream.makeAsyncIterator()
      self.subscribeResponse = subscribeResponse
    }

    var sentMessageTypes: [String] { withLock { _sentMessageTypes } }
    var cancelCall: (code: URLSessionWebSocketTask.CloseCode, reason: Data?)? { withLock { _cancelCall } }

    func resume() {}

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
      guard let json = Self.jsonObject(from: message),
            let type = json["type"] as? String else { return }

      withLock { _sentMessageTypes.append(type) }

      switch type {
      case "connection_init":
        continuation.yield(.string(#"{"type":"connection_ack"}"#))
        continuation.yield(.string(#"{"type":"ping"}"#))

      case "subscribe":
        let id = json["id"] as? String ?? ""
        switch subscribeResponse {
        case .success(let number):
          continuation.yield(.string(#"{"type":"next","id":"\#(id)","payload":{"data":{"number":\#(number)}}}"#))
          continuation.yield(.string(#"{"type":"complete","id":"\#(id)"}"#))

        case .error(let message):
          continuation.yield(.string(#"{"type":"error","id":"\#(id)","payload":[{"message":"\#(message)"}]}"#))
        }

      default:
        break
      }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
      var currentIterator = iterator
      let message = await currentIterator.next()
      iterator = currentIterator

      guard let message else { throw POSIXError(.ENOTCONN) }
      return message
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
      withLock { _cancelCall = (closeCode, reason) }
      continuation.finish()
    }

    private static func jsonObject(from message: URLSessionWebSocketTask.Message) -> [String: Any]? {
      let data: Data
      switch message {
      case .string(let string): data = Data(string.utf8)
      case .data(let messageData): data = messageData
      @unknown default: return nil
      }
      return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
      lock.lock()
      defer { lock.unlock() }
      return try body()
    }
  }

  private struct MockServerURLSession: WebSocketURLSession {
    let task: MockGraphQLWSServerTask

    func webSocketTask(with request: URLRequest) -> any WebSocketTask { task }
  }

  // MARK: - Helpers

  private func makeTransport(server: MockGraphQLWSServerTask) -> WebSocketTransport {
    WebSocketTransport(
      urlSession: MockServerURLSession(task: server),
      store: ApolloStore(),
      endpointURL: URL(string: "ws://localhost/graphql")!
    )
  }

  private func waitUntil(
    timeout: TimeInterval = 2,
    _ condition: @escaping @Sendable () -> Bool
  ) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
  }

  // MARK: - Tests

  func testSubscription_success_receivesDataAndCompletes() async throws {
    let server = MockGraphQLWSServerTask()
    let transport = makeTransport(server: server)

    var responses: [GraphQLResponse<NumberSubscription>] = []
    for try await response in try transport.send(
      subscription: NumberSubscription(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration()
    ) {
      responses.append(response)
    }

    XCTAssertEqual(responses.count, 1)
    XCTAssertEqual(responses.first?.data?.number, 42)

    let didSubscribe = await waitUntil { server.sentMessageTypes.contains("subscribe") }
    XCTAssertTrue(didSubscribe)
    XCTAssertEqual(server.sentMessageTypes.first, "connection_init")
    XCTAssertTrue(server.sentMessageTypes.contains("pong"), "Expected a pong in response to the server ping")
  }

  func testSubscription_serverError_finishesWithGraphQLErrors() async throws {
    let server = MockGraphQLWSServerTask(subscribeResponse: .error(message: "Something went wrong"))
    let transport = makeTransport(server: server)

    do {
      for try await _ in try transport.send(
        subscription: NumberSubscription(),
        fetchBehavior: .NetworkOnly,
        requestConfiguration: RequestConfiguration()
      ) {
        XCTFail("Expected the stream to fail")
      }
      XCTFail("Expected the stream to throw")
    } catch {
      guard case WebSocketTransport.Error.graphQLErrors(let errors) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(errors.count, 1)
      XCTAssertEqual(errors.first?.message, "Something went wrong")
    }
  }

  func testSubscription_writesResponseToCache() async throws {
    let server = MockGraphQLWSServerTask()
    let store = ApolloStore()
    let transport = WebSocketTransport(
      urlSession: MockServerURLSession(task: server),
      store: store,
      endpointURL: URL(string: "ws://localhost/graphql")!
    )

    for try await _ in try transport.send(
      subscription: NumberSubscription(),
      fetchBehavior: .NetworkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: true)
    ) {}

    let cached = try await store.load(NumberSubscription())
    XCTAssertEqual(cached?.data?.number, 42)
  }
}
