import Foundation

/// A `URLSession` that answers whatever a test tells it to, and nothing else.
///
/// Used by `WeFlixAuthClientTests` so every branch of the client's HTTP → sentence mapping is driven by a test.
/// It never reaches the network: `canInit` claims only the test host, and `startLoading` calls the test's own
/// handler.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    /// `.json(status, body)` — the usual case.
    static func json(_ status: Int, _ body: String) -> Handler {
        reply(status, Data(body.utf8), contentType: "application/json")
    }

    /// `.text(status, body)` — a proxy's 502, a captive portal's HTML: a body the client cannot decode.
    static func text(_ status: Int, _ body: String) -> Handler {
        reply(status, Data(body.utf8), contentType: "text/plain")
    }

    /// `.failure(error)` — no network, a timeout, TLS.
    static func failure(_ error: Error) -> Handler {
        { _ in throw error }
    }

    /// `.capturing(record, handler)` — let the test look at the request too.
    ///
    /// The request handed to a `URLProtocol` carries its body as an **`httpBodyStream`**, not as the `httpBody`
    /// the caller set (Foundation converts it on the way in), so the recording is given a copy whose `httpBody`
    /// has been read back out of the stream. Without that, "what did the client actually post?" is unanswerable.
    static func capturing(
        _ record: @escaping @Sendable (URLRequest) -> Void,
        _ handler: @escaping Handler,
    ) -> Handler {
        { request in
            record(requestWithBodyReadBack(request))

            return try handler(request)
        }
    }

    /// The request with `httpBody` refilled from `httpBodyStream`, when that is where the body is.
    private static func requestWithBodyReadBack(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else {
            return request
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)

            guard read > 0 else { break }

            data.append(buffer, count: read)
        }

        var copy = request
        copy.httpBody = data

        return copy
    }

    private static func reply(_ status: Int, _ data: Data, contentType: String) -> Handler {
        { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://weflix.test")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType],
            )!

            return (response, data)
        }
    }

    /// A session whose only protocol is this one.
    static func session(_ handler: @escaping Handler) -> URLSession {
        handlerStore.set(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]

        return URLSession(configuration: configuration)
    }

    /* ---------------------------------------------------------------------- */

    /// `URLProtocol` is instantiated by the loading system, not by the test, so the handler has to live
    /// somewhere reachable from the instance. One test at a time per process, which is how Swift Testing runs
    /// them by default.
    private static let handlerStore = HandlerBox()

    private final class HandlerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func set(_ newValue: @escaping Handler) {
            lock.lock()
            defer { lock.unlock() }
            handler = newValue
        }

        func current() -> Handler? {
            lock.lock()
            defer { lock.unlock() }

            return handler
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "weflix.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handlerStore.current() else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))

            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
