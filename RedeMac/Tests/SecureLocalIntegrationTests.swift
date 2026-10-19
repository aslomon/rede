import XCTest

@testable import Rede

/// Stale opt-ins stored as `true` must be inert under secure-local: no live session, no routing
/// plan, and a closed gate for every client the composition root hands out. AppState is built with
/// every settings value injected and pre-migrated, so the test neither reads nor writes the real
/// settings file.
@MainActor
final class SecureLocalIntegrationTests: XCTestCase {
  private func makeState(secureLocal: Bool, hasKey: Bool = true) -> AppState {
    var settings = AppSettings()
    settings.secureLocalModeEnabled = secureLocal
    settings.liveTranscriptionEnabled = true
    settings.purposeRoutingEnabled = true
    settings.didMigrateToModeConfigs = true
    settings.modesSchemaVersion = 4
    settings.hasAutoSelectedFastLocalModel = true
    settings.hadAccessibilityGrant = true
    return AppState(
      appSettings: settings, transcriptionSettings: TranscriptionSettings(),
      textImprovementSettings: TextImprovementSettings(),
      dampfAblassenSettings: DampfAblassenSettings(), emojiTextSettings: EmojiTextSettings(),
      prewarmEnginesAtLaunch: false, credentialPresence: { _ in hasKey })
  }

  private func automaticMode() -> ModeConfig {
    var mode = ModeConfig.default(for: .textImprover)
    mode.rewrite.purposeRouting = .automatic
    return mode
  }

  func testSecureLocalClosesTheGateAndBlocksLiveAndRoutingDespiteStoredTrue() {
    let state = makeState(secureLocal: true)

    XCTAssertFalse(state.remoteGate.allowsRemote())
    XCTAssertEqual(state.liveAvailability(backend: .remote), .unavailable(.secureLocal))
    XCTAssertNil(state.workflowRemoteContext(backend: .remote).live)
    XCTAssertFalse(state.workflowRemoteContext(backend: .remote).isRemoteAllowed())
    XCTAssertNil(
      state.purposeRoutingPlan(
        for: automaticMode(), targetIsSecureField: false, appName: "Mail",
        selection: nil, automaticContext: nil))
  }

  func testTurningSecureLocalOnClosesTheGateImmediately() {
    let state = makeState(secureLocal: false)
    let check = state.workflowRemoteContext(backend: .remote).isRemoteAllowed
    XCTAssertTrue(check())

    state.appSettings.secureLocalModeEnabled = true

    XCTAssertFalse(check(), "clients created earlier must see the new policy on their next attempt")
  }

  func testOnlineModeWithKeyBuildsAnAutomatikPlanButNeverForSecureFields() {
    let state = makeState(secureLocal: false)

    XCTAssertNotNil(
      state.purposeRoutingPlan(
        for: automaticMode(), targetIsSecureField: false, appName: "Mail",
        selection: nil, automaticContext: nil))
    XCTAssertNil(
      state.purposeRoutingPlan(
        for: automaticMode(), targetIsSecureField: true, appName: "Passwörter",
        selection: nil, automaticContext: nil))
  }

  func testNoKeyMeansNoRoutingPlan() {
    let state = makeState(secureLocal: false, hasKey: false)
    XCTAssertNil(
      state.purposeRoutingPlan(
        for: automaticMode(), targetIsSecureField: false, appName: "Mail",
        selection: nil, automaticContext: nil))
  }

  func testStoredEffortIsResolvedPerModelBeforeItReachesTheProvider() {
    let state = makeState(secureLocal: false)
    var luna = ModeConfig.default(for: .textImprover)
    XCTAssertEqual(state.resolvedReasoningEffort(for: luna), RewriteReasoningEffort.none)

    luna.rewrite.reasoningEffort = .xhigh
    XCTAssertEqual(state.resolvedReasoningEffort(for: luna), .xhigh)

    var legacy = luna
    legacy.rewrite.modelID = "gpt-5.4"
    XCTAssertNil(state.resolvedReasoningEffort(for: legacy), "legacy models never get an effort")
  }
}
