import XCTest

@testable import Rede

@MainActor
private final class ScriptedLiveSession: LiveSessionControlling {
  var snapshot = LiveTranscriptSnapshot()
  var phase: LiveTranscriptionController.Phase = .idle
  var outcome: LiveOutcome = .cancelled
  private(set) var configurations: [LiveConfiguration] = []
  private(set) var cancelCalls = 0

  func begin(_ configuration: LiveConfiguration) { configurations.append(configuration) }
  func finish() async -> LiveOutcome { outcome }
  func cancel() { cancelCalls += 1 }
}

/// Shared live helper, the pill presentation and the live / Automatik settings switches.
@MainActor
final class LiveAndRoutingControlTests: XCTestCase {
  // MARK: - WorkflowLiveSupport

  private func support(_ session: ScriptedLiveSession) -> WorkflowLiveSupport {
    WorkflowLiveSupport(makeSession: { session })
  }

  func testBeginPassesLanguageAndKeywordsAndNeverThrows() {
    let session = ScriptedLiveSession()
    let live = support(session)

    live.begin(language: "de", keywords: ["rede", "Anna"])

    XCTAssertEqual(session.configurations.count, 1)
    XCTAssertEqual(session.configurations.first?.language, "de")
    XCTAssertEqual(session.configurations.first?.keywords, ["rede", "Anna"])
  }

  func testCompletedTranscriptReplacesTheFilePath() async throws {
    let session = ScriptedLiveSession()
    session.outcome = .transcript("  Hallo Welt  ", LiveStats())
    let live = support(session)
    live.begin(language: "de", keywords: [])

    let text = try await live.finalTranscript()

    XCTAssertEqual(text, "Hallo Welt")
  }

  func testUnusableAndEmptyFinalsFallBackToTheFilePathWithoutMixing() async throws {
    for outcome in [
      LiveOutcome.unusable(.network), .unusable(.timeout), .unusable(.remoteNotAllowed),
      .transcript("   ", LiveStats())
    ] {
      let session = ScriptedLiveSession()
      session.outcome = outcome
      let live = support(session)
      live.begin(language: "de", keywords: [])

      let text = try await live.finalTranscript()
      XCTAssertNil(text, "\(outcome)")
    }
  }

  func testCancelledSessionIsTerminalAndThrows() async {
    let session = ScriptedLiveSession()
    session.outcome = .cancelled
    let live = support(session)
    live.begin(language: "de", keywords: [])

    do {
      _ = try await live.finalTranscript()
      XCTFail("a cancelled live session must abort the run")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }

  func testNoSessionMeansFilePathAndCancelIsHarmless() async throws {
    let live = support(ScriptedLiveSession())
    let text = try await live.finalTranscript()
    XCTAssertNil(text)
    live.cancel()
  }

  func testCancelReachesTheSessionAndRestartingCancelsTheOldOne() {
    let first = ScriptedLiveSession()
    let second = ScriptedLiveSession()
    var sessions = [first, second]
    let live = WorkflowLiveSupport(makeSession: { sessions.removeFirst() })

    live.begin(language: "de", keywords: [])
    live.begin(language: "de", keywords: [])
    XCTAssertEqual(first.cancelCalls, 1)

    live.cancel()
    XCTAssertEqual(second.cancelCalls, 1)
  }

  func testDisplayStateFollowsControllerPhase() {
    let session = ScriptedLiveSession()
    let live = support(session)
    XCTAssertNil(live.displayState)

    live.begin(language: "de", keywords: [])
    let table: [(LiveTranscriptionController.Phase, LiveDisplayState?)] = [
      (.idle, nil), (.connecting, .connecting), (.streaming, .streaming),
      (.finishing, .finishing), (.finished, nil), (.cancelled, nil),
      (.failed(.network), .failed(.network))
    ]
    for (phase, expected) in table {
      session.phase = phase
      XCTAssertEqual(live.displayState, expected, "\(phase)")
    }
  }

  func testWorkflowDefaultsFailClosedWithoutRemoteWiring() {
    let context = WorkflowRemoteContext()
    XCTAssertFalse(context.isRemoteAllowed())
    XCTAssertNil(context.live)
  }

  // MARK: - Pill presentation

  func testHiddenWithoutADisplayState() {
    let model = LiveTranscriptModel(snapshot: nil, state: nil)
    XCTAssertFalse(model.isVisible)
    XCTAssertNil(model.note)
  }

  func testNotesForConnectingListeningFinishingAndFailed() {
    let empty = LiveTranscriptSnapshot()
    XCTAssertEqual(LiveTranscriptModel(snapshot: empty, state: .connecting).note, .connecting)
    XCTAssertEqual(LiveTranscriptModel(snapshot: empty, state: .streaming).note, .listening)
    XCTAssertEqual(LiveTranscriptModel(snapshot: empty, state: .finishing).note, .finishing)
    XCTAssertEqual(
      LiveTranscriptModel(snapshot: empty, state: .failed(.network)).note, .fallsBackToRecording)

    let talking = LiveTranscriptSnapshot(stableText: "Hallo", provisionalText: "Welt", revision: 3)
    XCTAssertNil(LiveTranscriptModel(snapshot: talking, state: .streaming).note)
  }

  func testShortTextIsShownWholeWithStableAndProvisionalSplit() {
    let snapshot = LiveTranscriptSnapshot(
      stableText: "Hallo Anna", provisionalText: "wie geht", revision: 1)
    let tail = LiveTranscriptModel(snapshot: snapshot, state: .streaming).tail

    XCTAssertEqual(tail.stable, "Hallo Anna")
    XCTAssertEqual(tail.provisional, "wie geht")
    XCTAssertFalse(tail.isTruncated)
  }

  func testLongTextKeepsTheNewestWordsAnchoredAtAWordStart() {
    let words = (1...60).map { "wort\($0)" }
    let stable = words.prefix(50).joined(separator: " ")
    let provisional = words.suffix(10).joined(separator: " ")
    let tail = LiveTranscriptModel.tail(stable: stable, provisional: provisional)

    XCTAssertTrue(tail.isTruncated)
    XCTAssertTrue(tail.provisional.hasSuffix("wort60"))
    let shown = tail.stable + " " + tail.provisional
    XCTAssertLessThanOrEqual(shown.count, LiveTranscriptModel.tailLimit + 1)
    XCTAssertTrue(shown.hasPrefix("wort"), "window must start at a word boundary: \(shown)")
  }

  func testTailNeverLosesTheTrailingProvisionalWord() {
    let tail = LiveTranscriptModel.tail(
      stable: String(repeating: "abcdefgh ", count: 30), provisional: "ende")
    XCTAssertEqual(tail.provisional, "ende")
  }

  func testVoiceOverValueIsConstantWhileStreaming() {
    let early = LiveTranscriptSnapshot(stableText: "eins", provisionalText: "", revision: 1)
    let later = LiveTranscriptSnapshot(
      stableText: "eins zwei drei", provisionalText: "vier", revision: 9)
    XCTAssertEqual(
      LiveTranscriptModel(snapshot: early, state: .streaming).accessibilityValue,
      LiveTranscriptModel(snapshot: later, state: .streaming).accessibilityValue)
    XCTAssertEqual(
      LiveTranscriptModel(snapshot: later, state: .finishing).accessibilityValue,
      "eins zwei drei vier")
  }

  // MARK: - Live switch

  private func settings(secureLocal: Bool, live: Bool = true) -> AppSettings {
    var settings = AppSettings()
    settings.secureLocalModeEnabled = secureLocal
    settings.liveTranscriptionEnabled = live
    return settings
  }

  func testLiveStaysStoredButInertUnderSecureLocal() {
    let model = LiveSettingsModel(
      settings: settings(secureLocal: true), hasAPIKey: true, microphoneAuthorized: true)

    XCTAssertTrue(model.isOn, "stored value is preserved")
    XCTAssertFalse(model.isEffective)
    XCTAssertFalse(model.canToggle)
    XCTAssertEqual(model.block, .secureLocal)
  }

  func testLiveEffectiveOnlyWithKeyAndMicrophone() {
    func model(key: Bool, mic: Bool) -> LiveSettingsModel {
      LiveSettingsModel(
        settings: settings(secureLocal: false), hasAPIKey: key, microphoneAuthorized: mic)
    }
    XCTAssertTrue(model(key: true, mic: true).isEffective)
    XCTAssertEqual(model(key: false, mic: true).block, .noAPIKey)
    XCTAssertEqual(model(key: true, mic: false).block, .noMicrophone)
  }

  func testLiveToggleOnlyChangesItsOwnSetting() {
    let before = settings(secureLocal: false, live: false)
    let after = LiveSettingsModel(settings: before, hasAPIKey: true, microphoneAuthorized: true)
      .setting(true)

    XCTAssertTrue(after.liveTranscriptionEnabled)
    XCTAssertEqual(after.secureLocalModeEnabled, before.secureLocalModeEnabled)
    XCTAssertEqual(after.purposeRoutingEnabled, before.purposeRoutingEnabled)
  }

  // MARK: - Automatik switches

  func testAutomatikIsDisabledWithReasonUnderSecureLocal() {
    var base = AppSettings()
    base.secureLocalModeEnabled = true
    base.purposeRoutingEnabled = true
    let model = PurposeRoutingSettingsModel(settings: base, hasAPIKey: true)

    XCTAssertFalse(model.canToggle)
    XCTAssertEqual(model.block, .secureLocal)
    XCTAssertFalse(
      model.modeToggleEnabled(ModeConfig.default(for: .textImprover), rewriteBackend: .openai))
  }

  func testOnlyModesWithARewriteStepOfferAutomatik() {
    var base = AppSettings()
    base.secureLocalModeEnabled = false
    base.purposeRoutingEnabled = true
    let model = PurposeRoutingSettingsModel(settings: base, hasAPIKey: true)

    XCTAssertTrue(
      model.modeToggleEnabled(ModeConfig.default(for: .textImprover), rewriteBackend: .openai))
    XCTAssertTrue(
      model.modeToggleEnabled(ModeConfig.default(for: .emojiText), rewriteBackend: .openai),
      "Social rewrites too, so it may opt in")
    XCTAssertFalse(model.offersMode(ModeConfig.default(for: .transcription)))
    XCTAssertFalse(model.offersMode(ModeConfig.default(for: .localTranscription)))
    XCTAssertFalse(
      model.modeToggleEnabled(ModeConfig.default(for: .textImprover), rewriteBackend: .local))
  }

  func testAutomatikGlobalSwitchMustBeOnForTheModeSwitch() {
    var base = AppSettings()
    base.secureLocalModeEnabled = false
    let model = PurposeRoutingSettingsModel(settings: base, hasAPIKey: true)
    XCTAssertFalse(
      model.modeToggleEnabled(ModeConfig.default(for: .textImprover), rewriteBackend: .openai))
  }

  func testAutomatikEditsNeverTouchAnyUnrelatedPrivacySetting() {
    var base = AppSettings()
    base.secureLocalModeEnabled = false
    base.memoryContextEnabled = false
    base.semanticEmailMemoryEnabled = false
    base.archiveEnabled = false
    base.improvementDetectionEnabled = false
    var mode = ModeConfig.default(for: .textImprover)
    mode.rewrite.useAutomaticFieldContext = false
    mode.rewrite.useMemoryContext = false
    mode.rewrite.useSemanticEmailMemory = false
    let model = PurposeRoutingSettingsModel(settings: base, hasAPIKey: true)

    let settings = PurposeRoutingSettingsModel(
      settings: model.settingEnabled(true), hasAPIKey: true
    ).settingFieldText(false)
    let routed = model.settingMode(.automatic, on: mode)

    XCTAssertTrue(settings.purposeRoutingEnabled)
    XCTAssertFalse(settings.purposeRoutingIncludesFieldText)
    XCTAssertFalse(settings.memoryContextEnabled)
    XCTAssertFalse(settings.semanticEmailMemoryEnabled)
    XCTAssertFalse(settings.archiveEnabled)
    XCTAssertFalse(settings.improvementDetectionEnabled)
    XCTAssertFalse(settings.secureLocalModeEnabled)
    XCTAssertEqual(routed.rewrite.purposeRouting, .automatic)
    XCTAssertFalse(routed.rewrite.useAutomaticFieldContext)
    XCTAssertFalse(routed.rewrite.useMemoryContext)
    XCTAssertFalse(routed.rewrite.useSemanticEmailMemory)
  }
}
