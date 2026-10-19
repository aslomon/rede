import XCTest

@testable import Rede

/// The Automatik router is composed in ONE place. The policy gate must reach the Decisions client
/// and its transport, not only the router: otherwise a policy change while the credential is still
/// being read would not stop the request. Everything here is synthetic: a fake credential closure
/// and a URLProtocol that counts requests. No Keychain read, no network.
@MainActor
final class PurposeRouterCompositionTests: XCTestCase {
  override func setUp() {
    super.setUp()
    CompositionURLProtocol.reset()
  }

  private var context: DecisionContext {
    DecisionContext(dictatedText: "Please move our meeting to Wednesday.")
  }

  /// The real transport (credential wait, gate checks, request building) with a fake credential.
  private nonisolated static func client(
    gate: @escaping @Sendable () -> Bool, probe: CompositionProbe,
    credential: @escaping @Sendable () -> Void
  ) -> DecisionsClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CompositionURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return DecisionsClient(
      isRemoteAllowed: gate,
      transport: { body in
        let transport = OpenAIDecisionsTransport(
          session: session, isRemoteAllowed: gate,
          apiKey: {
            probe.recordCredential()
            credential()
            return "synthetic-test-key"
          })
        return try await transport.send(body)
      })
  }

  func testTheClientFactoryReceivesTheLivePolicyClosure() {
    let gate = RemoteAccessGate(secureLocalEnabled: false)
    var received: (@Sendable () -> Bool)?
    _ = AppState.makePurposeRouter(isRemoteAllowed: gate.allowsRemote) { allowed in
      received = allowed
      return DecisionsClient(isRemoteAllowed: allowed)
    }

    XCTAssertEqual(received?(), true)
    gate.update(secureLocalEnabled: true)
    XCTAssertEqual(received?(), false, "the client must follow the policy, not a captured Bool")
  }

  func testRevocationDuringTheCredentialWaitSendsNothing() async {
    let gate = RemoteAccessGate(secureLocalEnabled: false)
    let probe = CompositionProbe()
    let router = AppState.makePurposeRouter(isRemoteAllowed: gate.allowsRemote) { allowed in
      Self.client(gate: allowed, probe: probe) {
        Thread.sleep(forTimeInterval: 0.03)
        gate.update(secureLocalEnabled: true)  // the user turns secure-local on mid-lookup
      }
    }

    let decision = await router.route(context)

    XCTAssertEqual(decision.neutralReason, .remoteNotAllowed)
    XCTAssertEqual(probe.credentialCalls, 1, "the revocation must land DURING the credential wait")
    XCTAssertEqual(CompositionURLProtocol.requests, 0, "nothing may leave after the revocation")
  }

  /// Control: the fail-open composition this change removes. A router gate alone lets the request
  /// out, so the test above would catch a regression back to it.
  func testControlRouterGateAloneLetsTheRequestOutAfterRevocation() async {
    let gate = RemoteAccessGate(secureLocalEnabled: false)
    let probe = CompositionProbe()
    let failOpen: @Sendable () -> Bool = { true }
    let alwaysTrueClient = Self.client(gate: failOpen, probe: probe) {
      Thread.sleep(forTimeInterval: 0.03)
      gate.update(secureLocalEnabled: true)
    }
    let router = DecisionsPurposeRouter(
      client: alwaysTrueClient, isRemoteAllowed: gate.allowsRemote)

    _ = await router.route(context)

    XCTAssertEqual(CompositionURLProtocol.requests, 1, "this is the leak the composition closes")
  }

  func testOpenPolicyStillReachesTheTransport() async {
    let gate = RemoteAccessGate(secureLocalEnabled: false)
    let probe = CompositionProbe()
    let router = AppState.makePurposeRouter(isRemoteAllowed: gate.allowsRemote) { allowed in
      Self.client(gate: allowed, probe: probe) {}
    }

    _ = await router.route(context)

    XCTAssertEqual(probe.credentialCalls, 1)
    XCTAssertEqual(CompositionURLProtocol.requests, 1, "the gate must not block an allowed run")
  }

  func testAlreadyClosedPolicyTouchesNeitherCredentialNorNetwork() async {
    let gate = RemoteAccessGate(secureLocalEnabled: true)
    let probe = CompositionProbe()
    let router = AppState.makePurposeRouter(isRemoteAllowed: gate.allowsRemote) { allowed in
      Self.client(gate: allowed, probe: probe) {}
    }

    let decision = await router.route(context)

    XCTAssertEqual(decision.neutralReason, .remoteNotAllowed)
    XCTAssertEqual(probe.credentialCalls, 0)
    XCTAssertEqual(CompositionURLProtocol.requests, 0)
  }
}

final class CompositionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var credentials = 0
  var credentialCalls: Int { lock.withLock { credentials } }
  func recordCredential() { lock.withLock { credentials += 1 } }
}

private final class CompositionURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private static var count = 0
  static var requests: Int { lock.withLock { count } }
  static func reset() { lock.withLock { count = 0 } }

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.withLock { Self.count += 1 }
    client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
  }
  override func stopLoading() {}
}
