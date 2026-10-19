import XCTest

@testable import Rede

/// The one-time pre-mode migration must not move an EXISTING installation onto the recommended
/// model; only a brand-new installation starts there. Pure tests: no settings file is touched.
final class ModeMigrationTests: XCTestCase {
  private let legacy = ModeMigration.LegacySettings(
    textImprovement: TextImprovementSettings(),
    dampfAblassen: DampfAblassenSettings(),
    emojiText: EmojiTextSettings())

  private func migrate(
    existing: [String: ModeConfig] = [:], order: [String] = [],
    legacy: ModeMigration.LegacySettings? = nil, isExistingInstallation: Bool
  ) -> (modes: [String: ModeConfig], order: [String]) {
    ModeMigration.migratedModes(
      existing: existing, order: order, legacy: legacy ?? self.legacy,
      isExistingInstallation: isExistingInstallation)
  }

  private func model(_ result: [String: ModeConfig], _ slot: WorkflowType) -> String? {
    result[slot.rawValue]?.rewrite.modelID
  }

  func testExistingPreModeInstallationKeepsHistoricalSlotModels() {
    let result = migrate(isExistingInstallation: true).modes

    XCTAssertEqual(model(result, .textImprover), RewriteModelRegistry.strongModelID)
    XCTAssertEqual(model(result, .dampfAblassen), RewriteModelRegistry.strongModelID)
    XCTAssertEqual(model(result, .emojiText), RewriteModelRegistry.fastModelID)
    XCTAssertEqual(model(result, .transcription), RewriteModelRegistry.defaultModelID)
    XCTAssertEqual(model(result, .localTranscription), RewriteModelRegistry.defaultModelID)
  }

  func testBrandNewInstallationStartsOnRecommendedModel() {
    let result = migrate(isExistingInstallation: false).modes

    XCTAssertEqual(result.count, WorkflowType.allCases.count)
    for slot in WorkflowType.allCases {
      XCTAssertEqual(model(result, slot), RewriteModelRegistry.recommendedModelID, slot.rawValue)
      XCTAssertNil(result[slot.rawValue]?.rewrite.reasoningEffort)
      XCTAssertEqual(result[slot.rawValue]?.rewrite.purposeRouting, .off)
    }
  }

  func testDecisionIsTheFlagNotTheModeCount() {
    // Both inputs are identical (no stored modes); only the installation origin differs.
    let existing = migrate(isExistingInstallation: true).modes
    let fresh = migrate(isExistingInstallation: false).modes
    XCTAssertNotEqual(model(existing, .textImprover), model(fresh, .textImprover))
  }

  func testStoredModesAreNeverRewrittenWhateverTheFlag() {
    var stored = ModeConfig.default(for: .textImprover, preservingLegacyModels: true)
    stored.rewrite.modelID = "some-account-model"
    stored.userName = "Mein Mail-Modus"
    for flag in [true, false] {
      let result = migrate(
        existing: [WorkflowType.textImprover.rawValue: stored], isExistingInstallation: flag
      ).modes
      XCTAssertEqual(model(result, .textImprover), "some-account-model")
      XCTAssertEqual(result[WorkflowType.textImprover.rawValue]?.userName, "Mein Mail-Modus")
    }
  }

  func testLegacyPerWorkflowCustomizationsStillCarryOver() {
    var custom = legacy
    custom.textImprovement.customName = "Büro"
    custom.textImprovement.systemPrompt = "Eigener Prompt"
    custom.textImprovement.context = "Kontext"
    custom.dampfAblassen.customName = "Agent"
    custom.dampfAblassen.systemPrompt = "Eigener Agent-Prompt"
    custom.emojiText.customName = "Chat"
    custom.emojiText.emojiDensity = .viel

    let result = migrate(legacy: custom, isExistingInstallation: true).modes

    XCTAssertEqual(result[WorkflowType.textImprover.rawValue]?.userName, "Büro")
    XCTAssertEqual(
      result[WorkflowType.textImprover.rawValue]?.rewrite.systemPrompt, "Eigener Prompt")
    XCTAssertEqual(result[WorkflowType.textImprover.rawValue]?.rewrite.context, "Kontext")
    XCTAssertEqual(result[WorkflowType.dampfAblassen.rawValue]?.userName, "Agent")
    XCTAssertEqual(
      result[WorkflowType.dampfAblassen.rawValue]?.rewrite.systemPrompt, "Eigener Agent-Prompt")
    XCTAssertEqual(result[WorkflowType.emojiText.rawValue]?.userName, "Chat")
    XCTAssertEqual(result[WorkflowType.emojiText.rawValue]?.rewrite.emojiDensity, .viel)
  }

  func testStockPromptCraftTextIsReplacedByCuratedDefault() {
    var stock = legacy
    stock.dampfAblassen.systemPrompt = DampfAblassenSettings().systemPrompt

    let result = migrate(legacy: stock, isExistingInstallation: true).modes

    XCTAssertEqual(
      result[WorkflowType.dampfAblassen.rawValue]?.rewrite.systemPrompt,
      ModeDefaults.promptCraftSystemPrompt)
  }

  func testModeOrderIsCompletedWithoutReordering() {
    XCTAssertEqual(
      migrate(isExistingInstallation: false).order, WorkflowType.allCases.map(\.rawValue))

    let partial = migrate(order: ["emojiText", "custom-1"], isExistingInstallation: true).order
    XCTAssertEqual(Array(partial.prefix(2)), ["emojiText", "custom-1"])
    XCTAssertEqual(Set(partial), Set(WorkflowType.allCases.map(\.rawValue) + ["custom-1"]))
  }

  // MARK: - Installation-origin marker

  func testFreshSettingsAreNotMarkedAndDecodedSettingsAre() throws {
    XCTAssertFalse(AppSettings().wasDecodedFromStorage)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    XCTAssertTrue(decoded.wasDecodedFromStorage)
  }

  func testOriginMarkerIsNeverPersisted() throws {
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    let data = try JSONEncoder().encode(decoded)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNil(object["wasDecodedFromStorage"])
  }
}
