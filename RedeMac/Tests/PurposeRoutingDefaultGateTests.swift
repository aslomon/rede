import XCTest
@testable import Rede

final class PurposeRoutingDefaultGateTests: XCTestCase {
    func testDefaultClientRevocationBeforeChooseMakesZeroTransportAndCredentialCalls() async {
        let state = DefaultGateProbe(revokeAtCheck: 3)
        let router = DecisionsPurposeRouter(isRemoteAllowed: { state.allowed },
                                            makeDefaultClient: factory(state))
        let result = await router.route(context)
        XCTAssertEqual(result.neutralReason, .remoteNotAllowed)
        XCTAssertEqual(state.transportCalls, 0)
        XCTAssertEqual(state.credentialCalls, 0)
        XCTAssertEqual(DefaultGateURLProtocol.calls, 0)
    }

    func testDefaultClientRevocationDuringSyntheticCredentialLookupNeverSendsEvidence() async {
        let state = DefaultGateProbe()
        let router = DecisionsPurposeRouter(isRemoteAllowed: { state.allowed },
                                            makeDefaultClient: factory(state, revokeDuringLookup: true))
        let result = await router.route(context)
        XCTAssertEqual(result.neutralReason, .remoteNotAllowed)
        XCTAssertEqual(state.transportCalls, 1)
        XCTAssertEqual(state.credentialCalls, 1)
        XCTAssertEqual(DefaultGateURLProtocol.calls, 0)
    }

    func testExplicitClientBypassesDefaultFactoryAndPreservesInjection() async {
        let response = Data("{\"answers\":[{\"type\":\"refusal\",\"name\":\"purpose\"}]}".utf8)
        let client = DecisionsClient { _ in DecisionsHTTPResponse(data: response, statusCode: 200) }
        let router = DecisionsPurposeRouter(client: client, isRemoteAllowed: { true }, makeDefaultClient: { gate in
            XCTFail("Explicit client must not construct a default client")
            return DecisionsClient(isRemoteAllowed: gate)
        })
        let result = await router.route(context)
        XCTAssertEqual(result.neutralReason, .refusal)
    }

    override func setUp() {
        super.setUp()
        DefaultGateURLProtocol.reset()
    }

    private var context: DecisionContext { DecisionContext(dictatedText: "Please move our meeting to Wednesday.") }

    private func factory(_ state: DefaultGateProbe,
                         revokeDuringLookup: Bool = false) -> DecisionsPurposeRouter.ClientFactory {
        let configuration = OpenAIDecisionsTransport.makeConfiguration()
        configuration.protocolClasses = [DefaultGateURLProtocol.self]
        let session = OpenAIDecisionsTransport.makeSession(configuration: configuration)
        return { gate in
            let transport = OpenAIDecisionsTransport(session: session, isRemoteAllowed: gate, apiKey: {
                state.recordCredential()
                if revokeDuringLookup {
                    Thread.sleep(forTimeInterval: 0.03)
                    state.revoke()
                }
                return "synthetic-test-key"
            })
            return DecisionsClient(isRemoteAllowed: gate, transport: { body in
                state.recordTransport()
                return try await transport.send(body)
            })
        }
    }
}

private final class DefaultGateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let revokeAtCheck: Int?
    private var enabled = true
    private var checks = 0
    private var credentials = 0
    private var transports = 0
    init(revokeAtCheck: Int? = nil) { self.revokeAtCheck = revokeAtCheck }
    var allowed: Bool {
        lock.withLock {
            checks += 1
            if let revokeAtCheck, checks >= revokeAtCheck { enabled = false }
            return enabled
        }
    }
    var credentialCalls: Int { lock.withLock { credentials } }
    var transportCalls: Int { lock.withLock { transports } }
    func recordCredential() { lock.withLock { credentials += 1 } }
    func recordTransport() { lock.withLock { transports += 1 } }
    func revoke() { lock.withLock { enabled = false } }
}

private final class DefaultGateURLProtocol: URLProtocol, @unchecked Sendable {
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
