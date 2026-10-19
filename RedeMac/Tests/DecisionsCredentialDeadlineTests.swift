import XCTest
@testable import Rede

final class DecisionsCredentialDeadlineTests: XCTestCase {
    func testRoutingDeadlineDoesNotWaitForSynchronousCredentialLookupOrStartLateRequests() async {
        let state = SlowCredentialState()
        let completed = expectation(description: "Uncooperative lookup returned")
        let session = interceptedSession()
        defer { session.invalidateAndCancel() }
        let provider: @Sendable () -> String? = {
            let first = state.record()
            Thread.sleep(forTimeInterval: 0.3)
            if first { completed.fulfill() }
            return "synthetic-late-key"
        }
        let transport = OpenAIDecisionsTransport(session: session, apiKey: provider)
        var policy = PurposeRoutingPolicy()
        policy.timeout = .milliseconds(20)
        let router = makeRouter(transport, policy: policy)
        let began = Date()
        let result = await router.route(context)
        XCTAssertEqual(result.neutralReason, .timeout)
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.15)
        // A still-blocked native lookup must not spawn one blocked worker per subsequent route.
        for _ in 0..<12 {
            let newTransport = OpenAIDecisionsTransport(session: session, apiKey: provider)
            let newRouter = makeRouter(newTransport, policy: policy)
            let repeated = await newRouter.route(context)
            XCTAssertEqual(repeated.neutralReason, .timeout)
        }
        XCTAssertEqual(state.calls, 1)
        await fulfillment(of: [completed], timeout: 1)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(CredentialDeadlineURLProtocol.calls, 0)
    }

    func testInflightCancellationReturnsBeforeSynchronousCredentialAndNeverStartsLateRequest() async {
        let started = expectation(description: "Lookup started")
        let completed = expectation(description: "Lookup returned")
        let session = interceptedSession()
        defer { session.invalidateAndCancel() }
        let transport = OpenAIDecisionsTransport(session: session, apiKey: {
            started.fulfill()
            Thread.sleep(forTimeInterval: 0.3)
            completed.fulfill()
            return "synthetic-late-key"
        })
        let router = makeRouter(transport)
        let task = Task { await router.route(context) }
        await fulfillment(of: [started], timeout: 1)
        let began = Date()
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.isCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.15)
        await fulfillment(of: [completed], timeout: 1)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(CredentialDeadlineURLProtocol.calls, 0)
    }

    func testPolicyRevocationDuringLookupBlocksRequestWithoutCachingPermission() async {
        let state = CredentialPolicyState()
        let session = interceptedSession()
        defer { session.invalidateAndCancel() }
        let transport = OpenAIDecisionsTransport(session: session, isRemoteAllowed: { state.allowed }, apiKey: {
            Thread.sleep(forTimeInterval: 0.03)
            state.revoke()
            return "synthetic-test-key"
        })
        let router = DecisionsPurposeRouter(client: DecisionsClient { try await transport.send($0) },
                                            isRemoteAllowed: { state.allowed })
        let result = await router.route(context)
        XCTAssertEqual(result.neutralReason, .remoteNotAllowed)
        XCTAssertEqual(CredentialDeadlineURLProtocol.calls, 0)
    }

    private var context: DecisionContext { DecisionContext(dictatedText: "Please move our meeting to Wednesday.") }

    private func makeRouter(_ transport: OpenAIDecisionsTransport,
                            policy: PurposeRoutingPolicy = PurposeRoutingPolicy()) -> DecisionsPurposeRouter {
        DecisionsPurposeRouter(client: DecisionsClient { try await transport.send($0) }, policy: policy)
    }

    private func interceptedSession() -> URLSession {
        CredentialDeadlineURLProtocol.reset()
        let configuration = OpenAIDecisionsTransport.makeConfiguration()
        configuration.protocolClasses = [CredentialDeadlineURLProtocol.self]
        return OpenAIDecisionsTransport.makeSession(configuration: configuration)
    }
}

private final class SlowCredentialState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func record() -> Bool { lock.withLock { count += 1; return count == 1 } }
}

private final class CredentialDeadlineURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var count = 0
    static var calls: Int { lock.withLock { count } }
    static func reset() { lock.withLock { count = 0 } }
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    override func stopLoading() {}
}

private final class CredentialPolicyState: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    var allowed: Bool { lock.withLock { enabled } }
    func revoke() { lock.withLock { enabled = false } }
}
