import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

@_spi(Internal) import ApolloAPI
@testable import ApolloWebSocket

/// Tests for ``WebSocketConnection``, which wraps `WebSocketTask` and adapts its receive errors for the
/// transport's stream-based receive loop.
final class WebSocketConnectionTests: XCTestCase {

  // MARK: - Mock

  private final class MockWebSocketTask: WebSocketTask, @unchecked Sendable {
    private let lock = NSLock()

    private var _isResumed = false
    private var _sentMessages: [URLSessionWebSocketTask.Message] = []
    private var _receivedMessages: [URLSessionWebSocketTask.Message]
    private var _cancelCall: (code: URLSessionWebSocketTask.CloseCode, reason: Data?)?
    private let _receiveError: (any Error)?
    private let _sendError: (any Error)?

    init(
      receivedMessages: [URLSessionWebSocketTask.Message] = [],
      receiveError: (any Error)? = nil,
      sendError: (any Error)? = nil
    ) {
      self._receivedMessages = receivedMessages
      self._receiveError = receiveError
      self._sendError = sendError
    }

    var isResumed: Bool { withLock { _isResumed } }
    var sentMessages: [URLSessionWebSocketTask.Message] { withLock { _sentMessages } }
    var cancelCall: (code: URLSessionWebSocketTask.CloseCode, reason: Data?)? { withLock { _cancelCall } }

    func resume() {
      withLock { _isResumed = true }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
      if let error = withLock({ _sendError }) { throw error }
      withLock { _sentMessages.append(message) }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
      if let error = withLock({ _receiveError }) { throw error }
      if let message = withLock({ _receivedMessages.isEmpty ? nil : _receivedMessages.removeFirst() }) {
        return message
      }
      throw POSIXError(.ENOTCONN)
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
      withLock { _cancelCall = (closeCode, reason) }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
      lock.lock()
      defer { lock.unlock() }
      return try body()
    }
  }

  // MARK: - Helpers

  private func messageDescription(_ message: URLSessionWebSocketTask.Message) -> String? {
    guard case .string(let string) = message else { return nil }
    return string
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

  func testOpenConnection_resumesTaskAndSendsConnectionInit() async throws {
    let task = MockWebSocketTask(receivedMessages: [.string(#"{"type":"connection_ack"}"#)])
    let connection = WebSocketConnection(task: task)

    let stream = connection.openConnection(connectingPayload: ["token": "abc"])
    var receivedCount = 0
    for try await _ in stream {
      receivedCount += 1
      break
    }

    XCTAssertEqual(receivedCount, 1)
    XCTAssertTrue(task.isResumed)

    let didSend = await waitUntil { !task.sentMessages.isEmpty }
    XCTAssertTrue(didSend)
    let sent = try XCTUnwrap(messageDescription(task.sentMessages[0]))
    XCTAssertTrue(sent.contains(#""type":"connection_init""#), "Unexpected message: \(sent)")
    XCTAssertTrue(sent.contains(#""token":"abc""#), "Unexpected message: \(sent)")
  }

  func testOpenConnection_clientCancellationError_endsStreamWithoutError() async throws {
    let task = MockWebSocketTask(receiveError: URLError(.cancelled))
    let connection = WebSocketConnection(task: task)

    var receivedCount = 0
    for try await _ in connection.openConnection() {
      receivedCount += 1
    }

    XCTAssertEqual(receivedCount, 0)
  }

  func testOpenConnection_posixENOTCONN_endsStreamWithoutError() async throws {
    let task = MockWebSocketTask(receiveError: POSIXError(.ENOTCONN))
    let connection = WebSocketConnection(task: task)

    var receivedCount = 0
    for try await _ in connection.openConnection() {
      receivedCount += 1
    }

    XCTAssertEqual(receivedCount, 0)
  }

  func testClose_cancelsTaskWithCloseCode() {
    let task = MockWebSocketTask()
    let connection = WebSocketConnection(task: task)

    connection.close(with: .normalClosure)

    XCTAssertEqual(task.cancelCall?.code, .normalClosure)
  }

  func testSend_whenTaskSendFails_cancelsTask() async throws {
    let task = MockWebSocketTask(sendError: URLError(.cannotConnectToHost))
    let connection = WebSocketConnection(task: task)

    connection.send(.string(#"{"type":"ping"}"#))

    let didCancel = await waitUntil { task.cancelCall != nil }
    XCTAssertTrue(didCancel)
    XCTAssertEqual(task.cancelCall?.code, .goingAway)
  }
}
