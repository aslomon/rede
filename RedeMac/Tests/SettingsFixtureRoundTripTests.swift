import XCTest

@testable import Rede

/// Round-trips the root-sanitized installed-settings fixture: every existing key and model choice
/// must survive, and the only difference after a re-save is additive. Read-only; no file I/O.
final class SettingsFixtureRoundTripTests: XCTestCase {
  private func decodeFixture() throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: SanitizedSettingsFixture.appJSON())
  }

  private func appObject() throws -> [String: Any] {
    let data = try SanitizedSettingsFixture.appJSON()
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  func testFixtureKeepsHuggingFaceSelectionAndPreMigratedState() throws {
    let settings = try decodeFixture()

    XCTAssertEqual(settings.selectedLocalLLM.modelID, "hf-ggml-org-gemma-4-e4b-it-gguf")
    XCTAssertEqual(settings.selectedLocalLLM.runtime, .llamaCpp)
    XCTAssertTrue(settings.didMigrateToModeConfigs)
    XCTAssertEqual(settings.modesSchemaVersion, 4)
    XCTAssertEqual(settings.modeOrder, WorkflowType.allCases.map(\.rawValue))
  }

  func testFixtureKeepsEveryStoredModelChoice() throws {
    let settings = try decodeFixture()
    let expected: [WorkflowType: String] = [
      .textImprover: "gpt-5.4", .dampfAblassen: "gpt-5.4", .emojiText: "gpt-4o-mini",
      .transcription: "gpt-4o", .localTranscription: "gpt-4o"
    ]
    XCTAssertEqual(settings.modes.count, 5)
    for (slot, modelID) in expected {
      XCTAssertEqual(settings.modes[slot.rawValue]?.rewrite.modelID, modelID, slot.rawValue)
    }
  }

  func testFixtureDecodesNewKeysToInertDefaults() throws {
    let settings = try decodeFixture()

    XCTAssertFalse(settings.liveTranscriptionEnabled)
    XCTAssertFalse(settings.purposeRoutingEnabled)
    XCTAssertTrue(settings.purposeRoutingIncludesFieldText)
    XCTAssertEqual(settings.dismissedModelOffers, [])
    for mode in settings.modes.values {
      XCTAssertNil(mode.rewrite.reasoningEffort)
      XCTAssertEqual(mode.rewrite.purposeRouting, .off)
    }
  }

  func testFixtureExistingPrivacyChoicesAreUntouched() throws {
    let settings = try decodeFixture()

    XCTAssertFalse(settings.secureLocalModeEnabled)
    XCTAssertTrue(settings.archiveEnabled)
    XCTAssertTrue(settings.memoryContextEnabled)
    XCTAssertTrue(settings.semanticEmailMemoryEnabled)
    XCTAssertTrue(settings.improvementDetectionEnabled)
  }

  func testLaunchMigrationsAreNoOpsForTheFixture() throws {
    // Both one-time launch migrations are guarded by these two values, so an installed settings
    // file like the fixture triggers no launch write from them.
    let settings = try decodeFixture()
    XCTAssertTrue(settings.didMigrateToModeConfigs)
    XCTAssertGreaterThanOrEqual(settings.modesSchemaVersion, 4)
  }

  func testResaveOnlyAddsNewKeysAndChangesNoExistingValue() throws {
    let original = try appObject()
    let encoded = try JSONEncoder().encode(try decodeFixture())
    let resaved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    for (key, value) in original where key != "modes" {
      XCTAssertEqual(
        NSDictionary(dictionary: [key: value]),
        NSDictionary(dictionary: [key: resaved[key] as Any]),
        key)
    }
    XCTAssertEqual(
      Set(resaved.keys).subtracting(original.keys),
      [
        "liveTranscriptionEnabled", "purposeRoutingEnabled", "purposeRoutingIncludesFieldText",
        "dismissedModelOffers"
      ])
    XCTAssertTrue(Set(original.keys).isSubset(of: resaved.keys), "no existing key may disappear")
  }

  func testResavedModesKeepEveryOriginalRewriteValue() throws {
    let original = try XCTUnwrap(appObject()["modes"] as? [String: [String: Any]])
    let encoded = try JSONEncoder().encode(try decodeFixture())
    let resaved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let resavedModes = try XCTUnwrap(resaved["modes"] as? [String: [String: Any]])

    for (slot, mode) in original {
      let before = try XCTUnwrap(mode["rewrite"] as? [String: Any])
      let after = try XCTUnwrap(resavedModes[slot]?["rewrite"] as? [String: Any])
      for (key, value) in before {
        XCTAssertEqual(
          NSDictionary(dictionary: [key: value]),
          NSDictionary(dictionary: [key: after[key] as Any]),
          "\(slot).\(key)")
      }
      XCTAssertEqual(after["purposeRouting"] as? String, "off", slot)
      XCTAssertNil(after["reasoningEffort"], slot)
    }
  }

  func testRoundTripPreservesTheDecodedValues() throws {
    let first = try decodeFixture()
    let second = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(first))

    XCTAssertEqual(second.selectedLocalLLM, first.selectedLocalLLM)
    XCTAssertEqual(second.modeOrder, first.modeOrder)
    XCTAssertEqual(
      second.modes.mapValues(\.rewrite.modelID), first.modes.mapValues(\.rewrite.modelID))
  }
}
