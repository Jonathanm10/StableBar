import Foundation
import os
@testable import StableBar

/// Serves canned responses and redirects to a URLSession, and logs every request it receives.
/// Tests use hosts of their own, so tests running in parallel don't collide.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var responses: [URL: Data] = [:]
        var redirects: [URL: URL] = [:]
        var requests: [URLRequest] = []
        /// The requests waiting for each held URL's response.
        var held: [URL: [StubURLProtocol]] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func serve(_ data: Data, at url: URL) {
        state.withLock { $0.responses[url] = data }
    }

    static func redirect(_ from: URL, to: URL) {
        state.withLock { $0.redirects[from] = to }
    }

    static var requests: [URLRequest] { state.withLock { $0.requests } }

    /// Holds the responses for `url` until `release(url)`, so a test can act while a request waits for one.
    static func hold(_ url: URL) {
        state.withLock { $0.held[url] = [] }
    }

    /// Whether a request for `url` waits for its held response.
    static func isHolding(_ url: URL) -> Bool {
        state.withLock { $0.held[url]?.isEmpty == false }
    }

    static func release(_ url: URL) {
        for request in state.withLock({ $0.held.removeValue(forKey: url) }) ?? [] { request.respond() }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration, delegate: SourceRedirectGuard(), delegateQueue: nil)
    }

    /// Only web requests: a file URL, such as a test's local Store, loads from disk and isn't logged.
    override class func canInit(with request: URLRequest) -> Bool { ["http", "https"].contains(request.url?.scheme) }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return client?.urlProtocol(self, didFailWithError: URLError(.badURL)) ?? () }
        let received = request
        let held = Self.state.withLock { state in
            state.requests.append(received)
            state.held[url]?.append(self)
            return state.held[url] != nil
        }
        if !held { respond() }
    }

    private func respond() {
        let url = request.url!
        let (data, target) = Self.state.withLock { ($0.responses[url], $0.redirects[url]) }
        if let target {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            var next = URLRequest(url: target)
            next.allHTTPHeaderFields = request.allHTTPHeaderFields
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}
