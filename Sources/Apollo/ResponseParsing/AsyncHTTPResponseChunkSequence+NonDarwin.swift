#if !canImport(Darwin)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An ``AsyncChunkSequence`` implementation for platforms without `URLSession.AsyncBytes` (such as Android and other
/// Linux-based platforms). It parses the chunks of an HTTP multi-part response from a stream of raw `Data` chunks,
/// using the multi-part boundary specified by the `HTTPURLResponse` to split the data into chunks as it is received.
///
/// This mirrors the Darwin `AsyncHTTPResponseChunkSequence` implementation. The underlying `Data` stream is produced
/// by ``URLSessionDataTaskChunkLoader`` from `URLSessionDataDelegate` callbacks.
public struct AsyncHTTPResponseChunkSequence: AsyncChunkSequence {
  public typealias Element = Data

  private let stream: AsyncThrowingStream<Data, Error>
  private let boundary: Data?

  init(response: HTTPURLResponse?, stream: AsyncThrowingStream<Data, Error>) {
    self.stream = stream

    if let boundaryString = response?.multipartHeaderComponents.boundary?.data(using: .utf8) {
      self.boundary = MultipartResponseParsing.Delimiter + boundaryString
    } else {
      self.boundary = nil
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(stream.makeAsyncIterator(), boundary: boundary)
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    public typealias Element = Data

    private var underlyingIterator: AsyncThrowingStream<Data, Error>.Iterator

    private let boundary: Data?

    /// Data received from the underlying stream that has not yet been emitted. Unlike the Darwin implementation,
    /// a single underlying `Data` value may contain multiple chunks and boundaries, so any data remaining after a
    /// boundary must be buffered for the next call to `next()`.
    private var buffer = Data()

    private typealias Constants = MultipartResponseParsing

    init(
      _ underlyingIterator: AsyncThrowingStream<Data, Error>.Iterator,
      boundary: Data?
    ) {
      self.underlyingIterator = underlyingIterator
      self.boundary = boundary
    }

    public mutating func next() async throws -> Data? {
      while true {
        if let boundary, let boundaryRange = buffer.range(of: boundary) {
          var chunk = Data(buffer[buffer.startIndex..<boundaryRange.lowerBound])
          buffer.removeSubrange(buffer.startIndex..<boundaryRange.upperBound)

          formatAsChunk(&chunk)

          if !chunk.isEmpty {
            return chunk
          }
          continue
        }

        guard let next = try await self.underlyingIterator.next() else {
          var chunk = buffer
          buffer.removeAll()

          formatAsChunk(&chunk)

          return chunk.isEmpty ? nil : chunk
        }

        buffer.append(next)
      }
    }

    private func formatAsChunk(_ buffer: inout Data) {
      if buffer.prefix(Constants.CRLF.count) == Constants.CRLF {
        buffer.removeFirst(Constants.CRLF.count)
      }

      if buffer.starts(with: Constants.CloseDelimiter) {
        buffer.removeAll()
      }
    }
  }
}

#endif
