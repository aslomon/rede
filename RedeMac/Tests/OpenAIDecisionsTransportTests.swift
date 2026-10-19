import Foundation
import XCTest

@testable import Rede

final class OpenAIDecisionsTransportTests: XCTestCase {
    func testProductionConfigurationIsEphemeralAndBounded() {
        let configuration = OpenAIDecisionsTransport.makeConfiguration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 10)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 15)
    }

    func testMissingAndWhitespaceKeysFailBeforeAnyNetworkRequest() async {
        for key: String? in [nil, "", " \n"] {
            let transport = OpenAIDecisionsTransport(session: interceptedSession(), apiKey: { key })
            do {
                _ = try await transport.send(Data("{}".utf8))
                XCTFail("Expected missing key")
            } catch { XCTAssertEqual(error as? DecisionsClientError, .notConfigured) }
        }
        XCTAssertEqual(DecisionsTestURLProtocol.callCount, 0)
    }

    func testBuildsDirectHTTPSRequestAndReturnsResponse() async throws {
        DecisionsTestURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/decisions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.timeoutInterval, 10)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{}".utf8)
            )
        }
        let transport = OpenAIDecisionsTransport(session: interceptedSession(), apiKey: { "synthetic-test-key" })
        let response = try await transport.send(Data("{\"input\":\"Synthetic text\"}".utf8))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.data, Data("{}".utf8))
        XCTAssertEqual(DecisionsTestURLProtocol.callCount, 1)
    }

    func testRejectsNonHTTPResponse() async {
        DecisionsTestURLProtocol.setHandler { request in
            (
                URLResponse(
                    url: request.url!, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil),
                Data("{}".utf8)
            )
        }
        let transport = OpenAIDecisionsTransport(session: interceptedSession(), apiKey: { "synthetic-test-key" })
        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("Expected invalid response")
        } catch { XCTAssertEqual(error as? DecisionsClientError, .invalidResponse) }
    }

    func testNeverForwardsEvidenceToRedirectedEndpoint() async throws {
        DecisionsTestURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 307, httpVersion: nil,
                headerFields: ["Location": "https://synthetic.invalid/receive"])!
            return (response, Data())
        }
        let transport = OpenAIDecisionsTransport(session: interceptedSession(), apiKey: { "synthetic-test-key" })
        let response = try await transport.send(Data("SYNTHETIC_EVIDENCE".utf8))
        XCTAssertEqual(response.statusCode, 307)
        XCTAssertEqual(DecisionsTestURLProtocol.callCount, 1)
    }

    func testRejectsOversizedDeclaredResponseBeforeAccumulatingBody() async {
        DecisionsTestURLProtocol.setHandler { request in
            (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Length": "\(DecisionsClient.maximumResponseBytes + 1)"])!, Data("{}".utf8)
            )
        }
        await assertOversizedResponseIsRejected()
    }

    func testStopsOversizedChunkedOrIncorrectLengthResponsesDuringReception() async {
        for headers in [["Transfer-Encoding": "chunked"], ["Content-Length": "2"]] {
            DecisionsTestURLProtocol.reset()
            let stopped = expectation(description: "Oversized synthetic response cancelled")
            DecisionsTestURLProtocol.enableChunking(stopped: { stopped.fulfill() })
            DecisionsTestURLProtocol.setHandler { request in
                (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!,
                    Data(repeating: 65, count: DecisionsClient.maximumResponseBytes * 8)
                )
            }
            await assertOversizedResponseIsRejected()
            await fulfillment(of: [stopped], timeout: 2)
            XCTAssertLessThan(DecisionsTestURLProtocol.sentBytes, DecisionsClient.maximumResponseBytes * 8)
            XCTAssertGreaterThan(DecisionsTestURLProtocol.stoppedCalls, 0)
        }
    }

    func testCancellationStopsAnActiveChunkedResponse() async {
        let firstChunk = expectation(description: "Synthetic response started")
        let stopped = expectation(description: "Synthetic response cancelled")
        DecisionsTestURLProtocol.enableChunking(
            firstChunk: { firstChunk.fulfill() }, stopped: { stopped.fulfill() })
        DecisionsTestURLProtocol.setHandler { request in
            (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Transfer-Encoding": "chunked"])!,
                Data(repeating: 65, count: DecisionsClient.maximumResponseBytes * 8)
            )
        }
        let transport = OpenAIDecisionsTransport(session: interceptedSession(), apiKey: { "synthetic-test-key" })
        let task = Task { try await transport.send(Data("{}".utf8)) }
        await fulfillment(of: [firstChunk], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertLessThan(DecisionsTestURLProtocol.sentBytes, DecisionsClient.maximumResponseBytes)
    }

    private func assertOversizedResponseIsRejected(file: StaticString = #filePath, line: UInt = #line) async {
        let transport = OpenAIDecisionsTransport(session: interceptedSession(), apiKey: { "synthetic-test-key" })
        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("Expected size rejection", file: file, line: line)
        } catch { XCTAssertEqual(error as? DecisionsClientError, .invalidResponse, file: file, line: line) }
    }

    override func setUp() {
        super.setUp()
        DecisionsTestURLProtocol.reset()
    }

    private func interceptedSession() -> URLSession {
        let configuration = OpenAIDecisionsTransport.makeConfiguration()
        configuration.protocolClasses = [DecisionsTestURLProtocol.self]
        return OpenAIDecisionsTransport.makeSession(configuration: configuration)
    }
}

private final class DecisionsTestURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (URLResponse, Data)
    private static let lock = NSLock()
    private static var handler: Handler?
    private static var calls = 0
    private static var chunking = false
    private static var firstChunk: (() -> Void)?
    private static var onStop: (() -> Void)?
    private static var transmitted = 0
    private static var stopped = 0
    private let deliveryLock = NSLock()
    private var isStopped = false
    private var pendingDelivery: DispatchWorkItem?
    private var stoppedCallback: (() -> Void)?

    static var sentBytes: Int { lock.withLock { transmitted } }
    static var stoppedCalls: Int { lock.withLock { stopped } }

    static func enableChunking(firstChunk: (() -> Void)? = nil, stopped: (() -> Void)? = nil) {
        lock.withLock {
            chunking = true
            Self.firstChunk = firstChunk
            onStop = stopped
        }
    }

    static var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        calls = 0
        chunking = false
        firstChunk = nil
        onStop = nil
        transmitted = 0
        stopped = 0
    }

    static func setHandler(_ value: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handler = value
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.calls += 1
        let handler = Self.handler
        let onStop = Self.onStop
        Self.lock.unlock()
        deliveryLock.withLock { stoppedCallback = onStop }
        guard let handler else {
            XCTFail("Unexpected transport request")
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            if let response = response as? HTTPURLResponse, response.statusCode == 307,
               let location = response.value(forHTTPHeaderField: "Location"), let url = URL(string: location) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: url), redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if Self.lock.withLock({ Self.chunking }) {
                deliverChunk(data, offset: 0)
            } else {
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {
        let callback = deliveryLock.withLock { () -> (() -> Void)? in
            guard !isStopped else { return nil }
            isStopped = true
            pendingDelivery?.cancel()
            return stoppedCallback
        }
        Self.lock.withLock { Self.stopped += 1 }
        callback?()
    }

    private func deliverChunk(_ data: Data, offset: Int) {
        guard !deliveryLock.withLock({ isStopped }) else { return }
        let end = min(offset + 65_536, data.count)
        let firstChunk = Self.lock.withLock { () -> (() -> Void)? in
            Self.transmitted += end - offset
            return offset == 0 ? Self.firstChunk : nil
        }
        client?.urlProtocol(self, didLoad: data.subdata(in: offset..<end))
        firstChunk?()
        guard end < data.count else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.deliverChunk(data, offset: end) }
        deliveryLock.withLock { pendingDelivery = work }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20), execute: work)
    }
}
