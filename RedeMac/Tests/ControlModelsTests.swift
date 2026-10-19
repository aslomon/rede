import XCTest

@testable import Rede

/// Shared by the update control tests (`ControlModelsTests`, `UpdateHintTests`).
@MainActor
final class FakeUpdates: UpdateControlling {
  var status: UpdateService.Status = .idle(lastChecked: nil)
  var availableUpdateVersion: String?
  /// What `installStagedUpdateNow()` reports; the real service returns false without a handler.
  var installResult = true
  var automaticChecksEnabled = true
  var automaticDownloadsEnabled = true
  var canCheckForUpdates = true
  private(set) var checkNowCalls = 0
  private(set) var installCalls = 0

  func setAutomaticChecksEnabled(_ enabled: Bool) { automaticChecksEnabled = enabled }
  func setAutomaticDownloadsEnabled(_ enabled: Bool) { automaticDownloadsEnabled = enabled }
  func checkNow() { checkNowCalls += 1 }
  func installStagedUpdateNow() -> Bool {
    installCalls += 1
    return installResult
  }
}

/// State tables for the pure control models behind the new settings UI.
@MainActor
final class ControlModelsTests: XCTestCase {
  // MARK: - Updates

  private func updateModel(
    _ fake: FakeUpdates, busy: Bool = false, available: Bool = true
  ) -> UpdateSettingsModel {
    UpdateSettingsModel(service: fake, updatesAvailable: available, isBusy: { busy })
  }

  func testStatusLineMirrorsEveryServiceStatus() {
    let fake = FakeUpdates()
    let model = updateModel(fake)
    let table: [(UpdateService.Status, UpdateStatusLine)] = [
      (.idle(lastChecked: nil), .idle(lastChecked: nil)),
      (.checking, .checking),
      (.downloading(fraction: 0.5), .downloading(fraction: 0.5)),
      (.downloading(fraction: nil), .downloading(fraction: nil)),
      (.available(version: "1.2"), .available(version: "1.2")),
      (.staged(version: "1.2"), .staged(version: "1.2")),
      (.failed(.network), .failed(.network)),
      (.failed(.invalidSignature), .failed(.invalidSignature))
    ]
    for (status, line) in table {
      fake.status = status
      XCTAssertEqual(model.statusLine, line)
    }
  }

  func testUnavailableBuildNeverOffersActions() {
    let fake = FakeUpdates()
    fake.status = .staged(version: "1.2")
    let model = updateModel(fake, available: false)

    XCTAssertEqual(model.statusLine, .unavailable)
    XCTAssertFalse(model.canCheckNow)
    XCTAssertFalse(model.canInstallNow)
    XCTAssertFalse(model.canChangeDownloads)
  }

  func testDownloadControlFollowsChecksAndShowsTheEffectiveValue() {
    let fake = FakeUpdates()
    let model = updateModel(fake)
    XCTAssertTrue(model.canChangeDownloads)

    model.automaticChecks = false
    fake.automaticDownloadsEnabled = false  // the service reports the EFFECTIVE value

    XCTAssertFalse(model.canChangeDownloads)
    XCTAssertFalse(model.automaticDownloads)
  }

  func testInstallNowNeedsAStagedUpdateAndNoDictation() {
    let fake = FakeUpdates()
    fake.status = .staged(version: "1.2")

    let idle = updateModel(fake, busy: false)
    XCTAssertTrue(idle.canInstallNow)
    XCTAssertFalse(idle.installWaitsForDictation)
    idle.installNow()
    XCTAssertEqual(fake.installCalls, 1)

    let busy = updateModel(fake, busy: true)
    XCTAssertFalse(busy.canInstallNow)
    XCTAssertTrue(busy.installWaitsForDictation)
    busy.installNow()
    XCTAssertEqual(fake.installCalls, 1, "a busy dictation must never be interrupted")
  }

  func testManualCheckIsNotGatedByDictationButNotRepeatedWhileChecking() {
    let fake = FakeUpdates()
    let model = updateModel(fake, busy: true)
    model.checkNow()
    XCTAssertEqual(fake.checkNowCalls, 1)

    fake.status = .checking
    model.checkNow()
    XCTAssertEqual(fake.checkNowCalls, 1)
  }

  func testNothingToInstallWithoutStagedUpdate() {
    let fake = FakeUpdates()
    for status in [
      UpdateService.Status.available(version: "1.2"), .checking, .idle(lastChecked: nil)
    ] {
      fake.status = status
      XCTAssertFalse(updateModel(fake).canInstallNow)
    }
  }

  // MARK: - Model picker

  func testLunaIsFirstAndRecommendedForNewConfigurations() throws {
    let picker = ModelPickerModel(config: RewriteConfig())

    XCTAssertEqual(picker.options.first?.id, RewriteModelRegistry.recommendedModelID)
    XCTAssertEqual(picker.options.first?.badge, .recommended)
    XCTAssertEqual(picker.selectedModelID, RewriteModelRegistry.recommendedModelID)
  }

  func testStoredCustomModelIsKeptVisibleAsCustom() throws {
    var config = RewriteConfig()
    config.modelID = "my-fine-tune"
    let options = ModelPickerModel(config: config).options

    let custom = try XCTUnwrap(options.last)
    XCTAssertEqual(custom.id, "my-fine-tune")
    XCTAssertEqual(custom.badge, .custom)
  }

  func testAccountModelsAreBadgedAndNotDuplicated() {
    let options = ModelPickerModel(
      config: RewriteConfig(), accountModelIDs: ["gpt-4o", "gpt-9-account"]
    ).options

    XCTAssertEqual(options.filter { $0.id == "gpt-4o" }.count, 1)
    XCTAssertEqual(options.first { $0.id == "gpt-9-account" }?.badge, .account)
  }

  func testLunaOffersExactlyTheSelectableEfforts() {
    let picker = ModelPickerModel(config: RewriteConfig())
    XCTAssertEqual(picker.selectableEfforts, [.none, .medium, .high, .xhigh])
    XCTAssertTrue(picker.showsEffortControl)
    XCTAssertEqual(picker.effectiveEffort, RewriteReasoningEffort.none)
    XCTAssertFalse(picker.effectiveEffortIsSlow)
  }

  func testHighAndXhighAreSelectableAndFlaggedSlow() throws {
    for effort in [RewriteReasoningEffort.high, .xhigh] {
      let updated = ModelPickerModel(config: RewriteConfig()).selecting(effort: effort)
      XCTAssertEqual(updated.reasoningEffort, effort)
      XCTAssertTrue(ModelPickerModel(config: updated).effectiveEffortIsSlow)
    }
  }

  func testLegacyModelsHideTheEffortControlAndSendNothing() {
    var config = RewriteConfig()
    config.modelID = "gpt-5.4"
    let picker = ModelPickerModel(config: config)
    XCTAssertFalse(picker.showsEffortControl)
    XCTAssertNil(picker.effectiveEffort)
  }

  func testUnselectableEffortIsIgnored() {
    let picker = ModelPickerModel(config: RewriteConfig())
    XCTAssertNil(picker.selecting(effort: .low).reasoningEffort)
    XCTAssertNil(picker.selecting(effort: .max).reasoningEffort)
  }

  func testSwitchingToAModelWithoutThatEffortDropsTheStoredEffort() {
    var config = RewriteConfig()
    config.reasoningEffort = .xhigh

    XCTAssertNil(ModelPickerModel(config: config).selecting(modelID: "gpt-5.4").reasoningEffort)
    XCTAssertEqual(
      ModelPickerModel(config: config).selecting(modelID: "gpt-6-sol").reasoningEffort, .xhigh)
  }

  // MARK: - Recommended-model offer

  private func modes(_ models: [WorkflowType: String]) -> [String: ModeConfig] {
    var result: [String: ModeConfig] = [:]
    for (slot, model) in models {
      var mode = ModeConfig.default(for: slot)
      mode.rewrite.modelID = model
      result[slot.rawValue] = mode
    }
    return result
  }

  func testOfferTargetsOnlyOnlineRewriteModesNotYetOnLuna() {
    var stored = modes([.textImprover: "gpt-5.4", .emojiText: "gpt-4o-mini"])
    stored[WorkflowType.transcription.rawValue] = ModeConfig.default(for: .transcription)
    var local = ModeConfig.default(for: .dampfAblassen)
    local.rewrite.rewriteBackend = .local
    local.rewrite.modelID = "gpt-5.4"
    stored[WorkflowType.dampfAblassen.rawValue] = local

    XCTAssertEqual(
      RecommendedModelOffer.candidateModeIDs(in: stored), ["emojiText", "textImprover"])
  }

  func testAdoptingMovesOnlyCandidatesAndLeavesTheRestUntouched() {
    var stored = modes([
      .textImprover: "gpt-5.4", .emojiText: RewriteModelRegistry.recommendedModelID
    ])
    stored["textImprover"]?.rewrite.reasoningEffort = .high

    let adopted = RecommendedModelOffer.adopting(stored)

    XCTAssertEqual(
      adopted["textImprover"]?.rewrite.modelID, RewriteModelRegistry.recommendedModelID)
    XCTAssertNil(adopted["textImprover"]?.rewrite.reasoningEffort)
    XCTAssertEqual(adopted["emojiText"]?.rewrite.modelID, RewriteModelRegistry.recommendedModelID)
  }

  func testOfferHidesWhenDismissedOrNothingToOffer() {
    let stored = modes([.textImprover: "gpt-5.4"])
    XCTAssertTrue(
      RecommendedModelOffer.isVisible(modes: stored, dismissedOffers: [], onlineRewriteReady: true))
    XCTAssertFalse(
      RecommendedModelOffer.isVisible(
        modes: stored, dismissedOffers: [RecommendedModelOffer.offerID], onlineRewriteReady: true))
    XCTAssertFalse(
      RecommendedModelOffer.isVisible(modes: stored, dismissedOffers: [], onlineRewriteReady: false)
    )
    XCTAssertEqual(
      RecommendedModelOffer.dismissing([]), [RecommendedModelOffer.offerID])
    XCTAssertEqual(
      RecommendedModelOffer.dismissing([RecommendedModelOffer.offerID]),
      [RecommendedModelOffer.offerID])
  }
}
