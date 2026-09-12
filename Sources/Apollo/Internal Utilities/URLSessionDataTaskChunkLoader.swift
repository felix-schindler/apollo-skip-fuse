#if !canImport(Darwin)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Loads a `URLRequest` using a `URLSessionDataTask` and exposes the raw response body as an
/// `AsyncThrowingStream` of `Data` chunks, delivered by `URLSessionDataDelegate` callbacks.
///
/// This is used on platforms where `URLSession.AsyncBytes` / `URLSession.bytes(for:)` are unavailable, such as
/// Android. The delegate callbacks drive ``AsyncHTTPResponseChunkSequence``, which splits multi-part responses.
final class URLSessionDataTaskChunkLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {

  let chunks: AsyncThrowingStream<Data, Error>

  private let lock = NSLock()
  private var responseContinuation: CheckedContinuation<URLResponse, Error>?
  private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?
  private var task: URLSessionDataTask?
  private var session: URLSession?

  override init() {
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    self.chunks = AsyncThrowingStream { continuation = $0 }
    super.init()

    self.streamContinuation = continuation
    continuation.onTermination = { [weak self] _ in
      self?.cancel()
    }
  }

  deinit {
    cancel()
  }

  /// Starts the data task and waits for the initial response. The returned ``AsyncChunkSequence`` emits the
  /// response body as it is received.
  func start(
    request: URLRequest,
    configuration: URLSessionConfiguration
  ) async throws -> (any AsyncChunkSequence, URLResponse) {
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    let task = session.dataTask(with: request)

    withLock {
      self.session = session
      self.task = task
    }

    let response: URLResponse = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        withLock {
          self.responseContinuation = continuation
        }

        task.resume()
      }
    } onCancel: {
      cancel()
    }

    return (
      AsyncHTTPResponseChunkSequence(response: response as? HTTPURLResponse, stream: chunks),
      response
    )
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    let continuation = withLock {
      let continuation = self.responseContinuation
      self.responseContinuation = nil
      return continuation
    }

    continuation?.resume(returning: response)
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let continuation = withLock {
      self.streamContinuation
    }

    continuation?.yield(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    let (responseContinuation, streamContinuation) = withLock {
      let responseContinuation = self.responseContinuation
      let streamContinuation = self.streamContinuation
      self.responseContinuation = nil
      self.streamContinuation = nil
      return (responseContinuation, streamContinuation)
    }

    if let error {
      responseContinuation?.resume(throwing: error)
      streamContinuation?.finish(throwing: error)
    } else {
      // A task that completes without ever delivering a response (for example, a connection failure) must not
      // leave the caller waiting forever.
      responseContinuation?.resume(throwing: URLError(.badServerResponse))
      streamContinuation?.finish()
    }

    session.finishTasksAndInvalidate()
  }

  private func cancel() {
    let (task, session) = withLock {
      let task = self.task
      let session = self.session
      self.task = nil
      self.session = nil
      return (task, session)
    }

    task?.cancel()
    session?.invalidateAndCancel()
  }

  /// `NSLock` is marked `noasync`; locking must happen from synchronous contexts. All lock accesses go through
  /// this synchronous helper so that the async `start(request:configuration:)` can use it.
  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}

#endif
