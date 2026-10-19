import XCTest

@testable import Rede

private actor RecordingRouter: PurposeRouting {
  private(set) var contexts: [DecisionContext] = []
  private let decision: PurposeDecision

  init(_ decision: PurposeDecision) { self.decision = decision }

  func route(_ context: DecisionContext) async -> PurposeDecision {
    contexts.append(context)
    return decision
  }
}

/// Eligibility, the four-field context boundary and the cancel/fallback mapping of Automatik.
final class PurposeRoutingStepTests: XCTestCase {
  private let emailDecision = PurposeDecision(
    purpose: .email, confidence: 0.9, neutralReason: nil)

  private func inputs(
    routingEnabled: Bool = true, mode: PurposeRoutingMode = .automatic, secureLocal: Bool = false,
    backend: RewriteBackend = .openai, kind: ModeKind = .transcribeThenRewrite,
    hasKey: Bool = true, secureField: Bool = false, includesFieldText: Bool = true
  ) -> PurposeRoutingPlanner.Inputs {
    var settings = AppSettings()
    settings.purposeRoutingEnabled = routingEnabled
    settings.secureLocalModeEnabled = secureLocal
    settings.purposeRoutingIncludesFieldText = includesFieldText
    var config = ModeConfig.default(for: .textImprover)
    config.kind = kind
    config.rewrite.purposeRouting = mode
    return PurposeRoutingPlanner.Inputs(
      settings: settings, config: config, rewriteBackend: backend, hasAPIKey: hasKey,
      targetIsSecureField: secureField, appName: "Mail",
      selection: SelectionContext(
        selectedText: " Betreff ", surroundingText: "SECRET-SURROUNDING", appBundleID: "com.x"),
      automaticContext: AutomaticRewriteContext(
        text: "Hallo Anna", appBundleID: "com.x", appName: "Mail", windowTitle: "SECRET-TITLE"))
  }

  // MARK: - Eligibility

  func testEligibleRunProducesAPlan() {
    XCTAssertNotNil(
      PurposeRoutingPlanner.plan(inputs(), router: RecordingRouter(emailDecision)))
  }

  func testEveryMissingConditionSkipsRouting() {
    let router = RecordingRouter(emailDecision)
    let ineligible: [(String, PurposeRoutingPlanner.Inputs)] = [
      ("master off", inputs(routingEnabled: false)),
      ("mode off", inputs(mode: .off)),
      ("secure-local", inputs(secureLocal: true)),
      ("local rewrite", inputs(backend: .local)),
      ("transcribe only", inputs(kind: .transcribeOnly)),
      ("no key", inputs(hasKey: false)),
      ("secure field", inputs(secureField: true))
    ]
    for (name, input) in ineligible {
      XCTAssertNil(PurposeRoutingPlanner.plan(input, router: router), name)
    }
  }

  func testEveryRewritingKindIsEligibleAndPlainDictationNever() {
    let router = RecordingRouter(emailDecision)
    let expectations: [(ModeKind, Bool)] = [
      (.transcribeThenRewrite, true), (.transcribeThenEmoji, true), (.transcribeOnly, false)
    ]
    for (kind, eligible) in expectations {
      let plan = PurposeRoutingPlanner.plan(inputs(kind: kind), router: router)
      XCTAssertEqual(plan != nil, eligible, "\(kind)")
      XCTAssertEqual(kind.rewritesText, eligible, "\(kind)")
    }
  }

  func testSettingsOfferAutomatikForExactlyTheModesThePlannerAccepts() {
    let model = PurposeRoutingSettingsModel(settings: AppSettings(), hasAPIKey: true)
    for slot in WorkflowType.allCases {
      let config = ModeConfig.default(for: slot)
      XCTAssertEqual(
        model.offersMode(config), config.kind.rewritesText, "\(slot)")
    }
    XCTAssertTrue(model.offersMode(ModeConfig.default(for: .emojiText)), "Social is a rewrite")
    XCTAssertFalse(model.offersMode(ModeConfig.default(for: .transcription)))
    XCTAssertFalse(model.offersMode(ModeConfig.default(for: .localTranscription)))
  }

  func testStaleOptInsStayInertUnderSecureLocalAndNeverCallTheRouter() async {
    let router = RecordingRouter(emailDecision)
    let plan = PurposeRoutingPlanner.plan(inputs(secureLocal: true), router: router)

    let result = await PurposeRoutingStep.run(plan: plan, dictatedText: "Bitte Termin verschieben")

    XCTAssertNil(plan)
    XCTAssertEqual(result, .skipped)
    let calls = await router.contexts.count
    XCTAssertEqual(calls, 0)
  }

  // MARK: - Context boundary

  func testAdapterKeepsOnlyTheFourApprovedFields() throws {
    let plan = try XCTUnwrap(
      PurposeRoutingPlanner.plan(inputs(), router: RecordingRouter(emailDecision)))

    let context = DecisionContextAdapter.make(dictatedText: "Text", plan: plan)

    XCTAssertEqual(
      context,
      DecisionContext(
        dictatedText: "Text", selectedText: "Betreff", appName: "Mail", fieldText: "Hallo Anna"))
    let dump = String(describing: context)
    XCTAssertFalse(dump.contains("SECRET-SURROUNDING"))
    XCTAssertFalse(dump.contains("SECRET-TITLE"))
  }

  func testFieldTextCanBeOptedOutWithoutAffectingTheRest() throws {
    let plan = try XCTUnwrap(
      PurposeRoutingPlanner.plan(
        inputs(includesFieldText: false), router: RecordingRouter(emailDecision)))

    let context = DecisionContextAdapter.make(dictatedText: "Text", plan: plan)

    XCTAssertNil(context.fieldText)
    XCTAssertEqual(context.selectedText, "Betreff")
  }

  func testBlankValuesBecomeNil() throws {
    var input = inputs()
    input.appName = "  "
    input.selection = nil
    input.automaticContext = nil
    let plan = try XCTUnwrap(
      PurposeRoutingPlanner.plan(input, router: RecordingRouter(emailDecision)))

    let context = DecisionContextAdapter.make(dictatedText: "Text", plan: plan)

    XCTAssertNil(context.appName)
    XCTAssertNil(context.selectedText)
    XCTAssertNil(context.fieldText)
  }

  // MARK: - Result mapping

  private func run(_ decision: PurposeDecision) async throws -> PurposeRoutingResult {
    let plan = try XCTUnwrap(
      PurposeRoutingPlanner.plan(inputs(), router: RecordingRouter(decision)))
    return await PurposeRoutingStep.run(plan: plan, dictatedText: "Bitte Termin verschieben")
  }

  func testConfidentEmailIsDetected() async throws {
    let result = try await run(emailDecision)
    XCTAssertEqual(result.purpose, .email)
    XCTAssertEqual(result.note, .detected(.email))
    XCTAssertFalse(result.isCancelled)
  }

  func testConfidentOtherSaysNoSpecialPurpose() async throws {
    let result = try await run(
      PurposeDecision(purpose: .other, confidence: 0.9, neutralReason: nil))
    XCTAssertEqual(result.purpose, .other)
    XCTAssertEqual(result.note, .noSpecialPurpose)
  }

  func testTimeoutAndLowConfidenceFallBackToNeutralAndContinue() async throws {
    for reason in [NeutralReason.timeout, .lowConfidence, .lowMargin, .transport, .refusal] {
      let result = try await run(.neutral(reason))
      XCTAssertEqual(result.purpose, .other, "\(reason)")
      XCTAssertEqual(result.note, .fellBack(reason))
      XCTAssertFalse(result.isCancelled, "a timeout is not a cancel: \(reason)")
    }
  }

  func testBlockedOrNotRunMeansNoNoteAtAll() async throws {
    for reason in [NeutralReason.notEligible, .remoteNotAllowed, .noAPIKey] {
      let result = try await run(.neutral(reason))
      XCTAssertNil(result.note, "\(reason)")
      XCTAssertFalse(result.isCancelled)
    }
  }

  func testRouterCancellationIsTerminal() async throws {
    let result = try await run(.neutral(.cancelled))
    XCTAssertTrue(result.isCancelled)
    XCTAssertNil(result.note)
  }

  func testTaskCancelledBeforeRoutingNeverCallsTheRouter() async throws {
    let router = RecordingRouter(emailDecision)
    let plan = try XCTUnwrap(PurposeRoutingPlanner.plan(inputs(), router: router))

    let task = Task { () -> PurposeRoutingResult in
      await Task.yield()
      return await PurposeRoutingStep.run(plan: plan, dictatedText: "Bitte Termin verschieben")
    }
    task.cancel()
    let result = await task.value

    XCTAssertTrue(result.isCancelled)
    let calls = await router.contexts.count
    XCTAssertEqual(calls, 0)
  }

  func testCancellationHelperTreatsTimeoutAsNotCancel() {
    XCTAssertTrue(WorkflowCancellation.isTerminal(CancellationError()))
    XCTAssertTrue(WorkflowCancellation.isTerminal(URLError(.cancelled)))
    XCTAssertFalse(WorkflowCancellation.isTerminal(URLError(.timedOut)))
  }
}
