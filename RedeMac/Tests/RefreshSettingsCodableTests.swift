import XCTest

@testable import Rede

/// Additive-settings contract for the live / Automatik / reasoning-effort refresh: every new key
/// has a safe default, unknown values never fail a decode, nothing persisted is reinterpreted.
final class RefreshSettingsCodableTests: XCTestCase {
  private let huggingFaceSelectionID = "hf-ggml-org-gemma-4-e4b-it-gguf"

  private func decodeSettings(_ json: String) throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
  }

  private func decodeRewrite(_ json: String) throws -> RewriteConfig {
    try JSONDecoder().decode(RewriteConfig.self, from: Data(json.utf8))
  }

  // MARK: - Invariant guard

  func testWorkflowTypeKeepsExactlyFiveSlotsAndRawValues() {
    XCTAssertEqual(
      WorkflowType.allCases.map(\.rawValue),
      ["transcription", "localTranscription", "textImprover", "dampfAblassen", "emojiText"])
  }

  // MARK: - AppSettings: new keys

  func testEmptyAndLegacySettingsDecodeToOptInOffDefaults() throws {
    for json in ["{}", #"{"archiveEnabled": true, "secureLocalModeEnabled": false}"#] {
      let decoded = try decodeSettings(json)
      XCTAssertFalse(decoded.liveTranscriptionEnabled)
      XCTAssertFalse(decoded.purposeRoutingEnabled)
      XCTAssertTrue(decoded.purposeRoutingIncludesFieldText)
      XCTAssertEqual(decoded.dismissedModelOffers, [])
    }
  }

  func testNewKeysRoundTrip() throws {
    var settings = AppSettings()
    settings.liveTranscriptionEnabled = true
    settings.purposeRoutingEnabled = true
    settings.purposeRoutingIncludesFieldText = false
    settings.dismissedModelOffers = ["gpt-6-luna"]

    let decoded = try JSONDecoder().decode(
      AppSettings.self, from: JSONEncoder().encode(settings))

    XCTAssertTrue(decoded.liveTranscriptionEnabled)
    XCTAssertTrue(decoded.purposeRoutingEnabled)
    XCTAssertFalse(decoded.purposeRoutingIncludesFieldText)
    XCTAssertEqual(decoded.dismissedModelOffers, ["gpt-6-luna"])
  }

  func testLegacyKeysAreUntouchedByNewDefaults() throws {
    let decoded = try decodeSettings(
      #"{"modesSchemaVersion": 4, "memoryContextEnabled": true, "maxDictationMinutes": 12}"#)
    XCTAssertEqual(decoded.modesSchemaVersion, 4)
    XCTAssertTrue(decoded.memoryContextEnabled)
    XCTAssertEqual(decoded.maxDictationMinutes, 12)
  }

  func testNewSettingsDoNotBumpSchemaVersion() {
    XCTAssertEqual(AppSettings().modesSchemaVersion, 1)
  }

  // MARK: - Local LLM selection (Hugging-Face hazard)

  func testStoredHuggingFaceSelectionSurvivesDecode() throws {
    let decoded = try decodeSettings(
      """
      {"selectedLocalLLM": {"runtime": "llamaCpp", "modelID": "\(huggingFaceSelectionID)"}}
      """)
    XCTAssertEqual(decoded.selectedLocalLLM.modelID, huggingFaceSelectionID)
    XCTAssertEqual(decoded.selectedLocalLLM.runtime, .llamaCpp)
  }

  func testValidatorKeepsInstalledNonCatalogModel() {
    let selection = LocalLLMSelection(modelID: huggingFaceSelectionID)
    XCTAssertNil(LlamaCppModelCatalog.chatModel(for: huggingFaceSelectionID))

    let validated = LocalLLMSelectionValidator.validated(
      selection, installedModelIDs: [huggingFaceSelectionID])

    XCTAssertEqual(validated, selection)
  }

  func testValidatorKeepsCuratedCatalogModelEvenWhenNotInstalled() throws {
    let model = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    let selection = LocalLLMSelection(modelID: model.id)
    XCTAssertEqual(
      LocalLLMSelectionValidator.validated(selection, installedModelIDs: []), selection)
  }

  func testValidatorDropsUnknownOllamaTagAndKeepsEmptySelection() {
    XCTAssertEqual(
      LocalLLMSelectionValidator.validated(
        LocalLLMSelection(modelID: "gemma3:latest"), installedModelIDs: [huggingFaceSelectionID]),
      LocalLLMSelection())
    XCTAssertEqual(
      LocalLLMSelectionValidator.validated(LocalLLMSelection(), installedModelIDs: []),
      LocalLLMSelection())
  }

  @MainActor
  func testLaunchKeepsInstalledHuggingFaceSelection() throws {
    // Unique temp directory, intentionally not removed afterwards (the system temp area is cleaned
    // by the OS; the test never deletes files).
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("rede-hf-selection-\(UUID().uuidString)", isDirectory: true)
    let store = LlamaCppModelStore(rootDirectory: root)
    let model = HuggingFaceModelService.makeModel(
      repo: "ggml-org/gemma-4-E4B-it-GGUF", fileName: "gemma-4-E4B-it-Q4_K_M.gguf",
      sha256: "", sizeBytes: 5)
    XCTAssertEqual(model.id, huggingFaceSelectionID)
    try store.ensureRootExists()
    let finalURL = try store.finalURL(for: model)
    try Data("model".utf8).write(to: finalURL)
    try store.writeVerifiedManifest(for: model, fileURL: finalURL)

    // Every settings value is injected and pre-migrated, so launch neither reads nor schedules a
    // write of the real settings file.
    var settings = AppSettings()
    settings.selectedLocalLLM = LocalLLMSelection(modelID: huggingFaceSelectionID)
    settings.didMigrateToModeConfigs = true
    settings.modesSchemaVersion = 4
    settings.hasAutoSelectedFastLocalModel = true
    settings.hadAccessibilityGrant = true
    let state = AppState(
      appSettings: settings, transcriptionSettings: TranscriptionSettings(),
      textImprovementSettings: TextImprovementSettings(),
      dampfAblassenSettings: DampfAblassenSettings(), emojiTextSettings: EmojiTextSettings(),
      localModelManager: LocalModelManager(store: store), prewarmEnginesAtLaunch: false)

    XCTAssertEqual(state.appSettings.selectedLocalLLM.modelID, huggingFaceSelectionID)
  }

  // MARK: - RewriteConfig: reasoning effort and Automatik

  func testRewriteConfigMissingKeysDecodeToDefaults() throws {
    let config = try decodeRewrite(#"{"modelID": "gpt-5.4"}"#)
    XCTAssertNil(config.reasoningEffort)
    XCTAssertEqual(config.purposeRouting, .off)
  }

  func testRewriteConfigRoundTripsEffortAndAutomatik() throws {
    var config = RewriteConfig()
    config.reasoningEffort = RewriteReasoningEffort.xhigh
    config.purposeRouting = .automatic

    let decoded = try JSONDecoder().decode(RewriteConfig.self, from: JSONEncoder().encode(config))

    XCTAssertEqual(decoded.reasoningEffort, RewriteReasoningEffort.xhigh)
    XCTAssertEqual(decoded.purposeRouting, .automatic)
  }

  func testExplicitNoneEffortIsDistinctFromUnsetEffort() throws {
    var config = RewriteConfig()
    config.reasoningEffort = RewriteReasoningEffort.none

    let decoded = try JSONDecoder().decode(RewriteConfig.self, from: JSONEncoder().encode(config))

    XCTAssertEqual(decoded.reasoningEffort, RewriteReasoningEffort.none)
    XCTAssertNotNil(decoded.reasoningEffort)
  }

  func testUnsetEffortIsOmittedFromEncodedJSON() throws {
    let data = try JSONEncoder().encode(RewriteConfig())
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNil(object["reasoningEffort"])
  }

  func testUnknownEffortAndRoutingValuesFallBackWithoutFailingDecode() throws {
    for json in [
      #"{"modelID": "gpt-5.4", "reasoningEffort": "ultra", "purposeRouting": "always"}"#,
      #"{"modelID": "gpt-5.4", "reasoningEffort": 7, "purposeRouting": 3}"#,
      #"{"modelID": "gpt-5.4", "reasoningEffort": null, "purposeRouting": null}"#,
      #"{"modelID": "gpt-5.4", "reasoningEffort": {"a": 1}, "purposeRouting": [1]}"#
    ] {
      let config = try decodeRewrite(json)
      XCTAssertNil(config.reasoningEffort, json)
      XCTAssertEqual(config.purposeRouting, .off, json)
      XCTAssertEqual(config.modelID, "gpt-5.4", json)
    }
  }

  func testPurposeRoutingModeStoresOnlyTwoRawValues() {
    XCTAssertEqual(PurposeRoutingMode.allCases.map(\.rawValue), ["off", "automatic"])
  }

  // MARK: - Model defaults and preservation

  func testNewConfigurationsUseRecommendedModelWithUnsetEffort() {
    XCTAssertEqual(RewriteConfig().modelID, RewriteModelRegistry.recommendedModelID)
    XCTAssertNil(RewriteConfig().reasoningEffort)
    for slot in WorkflowType.allCases {
      XCTAssertEqual(
        ModeConfig.defaultRewrite(for: slot).modelID, RewriteModelRegistry.recommendedModelID)
      XCTAssertEqual(ModeConfig.default(for: slot).rewrite.purposeRouting, .off)
    }
  }

  func testLegacyDecodeFallbackStaysOnGpt4o() throws {
    XCTAssertEqual(RewriteModelRegistry.defaultModelID, "gpt-4o")
    XCTAssertEqual(try decodeRewrite("{}").modelID, "gpt-4o")
  }

  func testStoredModelChoiceIsPreservedExactly() throws {
    for id in ["gpt-4o", "gpt-5.4", "gpt-4o-mini", "gpt-6-luna", "some-account-model"] {
      let config = try decodeRewrite(#"{"modelID": "\#(id)"}"#)
      XCTAssertEqual(config.modelID, id)
    }
  }

  func testModeWithoutRewriteBlockKeepsPreviousSlotDefaults() throws {
    let expected: [WorkflowType: String] = [
      .textImprover: RewriteModelRegistry.strongModelID,
      .dampfAblassen: RewriteModelRegistry.strongModelID,
      .emojiText: RewriteModelRegistry.fastModelID,
      .transcription: RewriteModelRegistry.defaultModelID,
      .localTranscription: RewriteModelRegistry.defaultModelID
    ]
    for (slot, modelID) in expected {
      let mode = try JSONDecoder().decode(
        ModeConfig.self, from: Data(#"{"slot": "\#(slot.rawValue)"}"#.utf8))
      XCTAssertEqual(mode.rewrite.modelID, modelID, slot.rawValue)
    }
  }

  func testStoredModesRoundTripWithoutChangingTheirModel() throws {
    var settings = AppSettings()
    var email = ModeConfig.default(for: .textImprover)
    email.rewrite.modelID = RewriteModelRegistry.strongModelID
    settings.modes = [WorkflowType.textImprover.rawValue: email]

    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

    let stored = try XCTUnwrap(decoded.modes[WorkflowType.textImprover.rawValue])
    XCTAssertEqual(stored.rewrite.modelID, RewriteModelRegistry.strongModelID)
    XCTAssertEqual(stored.rewrite.purposeRouting, .off)
  }
}
