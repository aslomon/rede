import XCTest

@testable import Rede

/// Round-trip and forward/backward-compatibility tests for the persisted settings shape.
/// These guard the on-disk contract: `settings.json` is decoded with `decodeIfPresent`
/// migrations, and `modes` MUST serialize as a keyed object (not an array).
final class AppSettingsCodableTests: XCTestCase {

  private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  // MARK: - Round-trip

  func testDefaultSettingsPreferLocalProcessing() {
    XCTAssertTrue(AppSettings().secureLocalModeEnabled)
  }

  func testRoundTripPreservesModesAndNewFlags() throws {
    var settings = AppSettings(
      archiveEnabled: true,
      memoryContextEnabled: true,
      hadAccessibilityGrant: true
    )
    settings.userDisplayName = "Jason Rinnert"
    var emailMode = ModeConfig.default(for: .textImprover)
    emailMode.userName = "Mein E-Mail Modus"
    emailMode.rewrite.rewriteBackend = .local
    emailMode.rewrite.useMemoryContext = true
    settings.modes = [
      WorkflowType.transcription.rawValue: .default(for: .transcription),
      WorkflowType.textImprover.rawValue: emailMode,
    ]
    settings.modeOrder = [WorkflowType.transcription.rawValue, WorkflowType.textImprover.rawValue]

    let data = try makeEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    XCTAssertTrue(decoded.archiveEnabled)
    XCTAssertTrue(decoded.memoryContextEnabled)
    XCTAssertTrue(decoded.hadAccessibilityGrant)
    XCTAssertFalse(decoded.semanticEmailMemoryEnabled)
    XCTAssertEqual(decoded.selectedEmbeddingModelName, LlamaCppEmbeddingProvider.defaultModelID)
    XCTAssertEqual(decoded.userDisplayName, "Jason Rinnert")
    XCTAssertEqual(decoded.modes.count, 2)

    let decodedEmail = try XCTUnwrap(decoded.modes[WorkflowType.textImprover.rawValue])
    XCTAssertEqual(decodedEmail.userName, "Mein E-Mail Modus")
    XCTAssertEqual(decodedEmail.rewrite.rewriteBackend, .local)
    XCTAssertTrue(decodedEmail.rewrite.useMemoryContext)
    XCTAssertEqual(decodedEmail.slot, .textImprover)
    XCTAssertEqual(
      decoded.modeOrder, [WorkflowType.transcription.rawValue, WorkflowType.textImprover.rawValue])
  }

  func testRoundTripPreservesDynamicDuplicateModeAndOrder() throws {
    var settings = AppSettings()
    var clientEmail = ModeConfig.default(for: .textImprover)
    clientEmail.modeID = "email-client-a"
    clientEmail.userName = "E-Mail Kunde A"
    clientEmail.rewrite.context = "Use concise project-update style for Client A."

    settings.modes = [
      WorkflowType.textImprover.rawValue: .default(for: .textImprover),
      clientEmail.id: clientEmail,
    ]
    settings.modeOrder = [WorkflowType.textImprover.rawValue, clientEmail.id]

    let data = try makeEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    XCTAssertEqual(decoded.modeOrder, [WorkflowType.textImprover.rawValue, "email-client-a"])
    let decodedClientEmail = try XCTUnwrap(decoded.modes["email-client-a"])
    XCTAssertEqual(decodedClientEmail.id, "email-client-a")
    XCTAssertEqual(decodedClientEmail.slot, .textImprover)
    XCTAssertEqual(decodedClientEmail.userName, "E-Mail Kunde A")
    XCTAssertEqual(
      decodedClientEmail.rewrite.context,
      "Use concise project-update style for Client A."
    )
  }

  func testOrderedModeConfigsUsesPersistedOrderThenDefaultsThenCustomRemainder() {
    var email = ModeConfig.default(for: .textImprover)
    var clientEmail = ModeConfig.default(for: .textImprover)
    clientEmail.modeID = "email-client-a"
    clientEmail.userName = "E-Mail Kunde A"
    email.userName = "E-Mail"

    let ordered = AppState.orderedModeConfigs(
      modes: [
        WorkflowType.textImprover.rawValue: email,
        WorkflowType.transcription.rawValue: .default(for: .transcription),
        clientEmail.id: clientEmail,
      ],
      modeOrder: [clientEmail.id, WorkflowType.textImprover.rawValue]
    )

    XCTAssertEqual(
      ordered.map(\.id),
      ["email-client-a", WorkflowType.textImprover.rawValue, WorkflowType.transcription.rawValue]
    )
  }

  func testReorderedModeIDsMovesOnlyWithinBounds() {
    let order = ["a", "b", "c"]

    XCTAssertEqual(
      AppState.reorderedModeIDs(order, moving: "b", offset: -1),
      ["b", "a", "c"]
    )
    XCTAssertEqual(
      AppState.reorderedModeIDs(order, moving: "b", offset: 1),
      ["a", "c", "b"]
    )
    XCTAssertEqual(AppState.reorderedModeIDs(order, moving: "a", offset: -1), order)
    XCTAssertEqual(AppState.reorderedModeIDs(order, moving: "missing", offset: 1), order)
  }

  /// `modes` must encode as a JSON OBJECT keyed by WorkflowType.rawValue, never an array.
  /// A regression to an array shape would silently drop every persisted mode on the next load.
  func testModesEncodeAsKeyedObjectNotArray() throws {
    var settings = AppSettings()
    settings.modes = [
      WorkflowType.transcription.rawValue: .default(for: .transcription),
      WorkflowType.emojiText.rawValue: .default(for: .emojiText),
    ]

    let data = try makeEncoder().encode(settings)
    let object = try JSONSerialization.jsonObject(with: data)
    let root = try XCTUnwrap(object as? [String: Any])

    let modes = try XCTUnwrap(root["modes"] as? [String: Any], "modes must be a keyed object")
    XCTAssertFalse(root["modes"] is [Any], "modes must NOT be a JSON array")
    XCTAssertNotNil(modes[WorkflowType.transcription.rawValue])
    XCTAssertNotNil(modes[WorkflowType.emojiText.rawValue])
  }

  // MARK: - Backward compatibility (decodeIfPresent migrations)

  /// An OLD settings.json missing every v2 key must still decode, with the new flags
  /// defaulting to OFF (privacy-preserving opt-in defaults) and modes defaulting to empty.
  func testOldSettingsMissingNewKeysDecodesWithDefaults() throws {
    let legacyJSON = """
      {
        "hotkeyMode": "hold",
        "hasSeenOnboarding": true,
        "secureLocalModeEnabled": false
      }
      """
    let data = Data(legacyJSON.utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    XCTAssertEqual(decoded.hotkeyMode, .hold)
    XCTAssertTrue(decoded.hasSeenOnboarding)
    // New v2 keys absent -> safe defaults.
    XCTAssertFalse(decoded.archiveEnabled)
    XCTAssertFalse(decoded.memoryContextEnabled)
    XCTAssertFalse(decoded.semanticEmailMemoryEnabled)
    XCTAssertEqual(decoded.selectedEmbeddingModelName, LlamaCppEmbeddingProvider.defaultModelID)
    XCTAssertFalse(decoded.hadAccessibilityGrant)
    XCTAssertEqual(decoded.userDisplayName, "")
    XCTAssertTrue(decoded.modes.isEmpty)
    XCTAssertTrue(decoded.modeOrder.isEmpty)
    XCTAssertFalse(decoded.didMigrateToModeConfigs)
    XCTAssertEqual(decoded.modesSchemaVersion, 1)
  }

  /// A completely empty object must decode to a fully-defaulted struct (never throws).
  func testEmptyObjectDecodesToDefaults() throws {
    let data = Data("{}".utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded.hotkeyMode, .hold)
    XCTAssertFalse(decoded.archiveEnabled)
    XCTAssertFalse(decoded.memoryContextEnabled)
    XCTAssertFalse(decoded.semanticEmailMemoryEnabled)
    XCTAssertEqual(decoded.selectedEmbeddingModelName, LlamaCppEmbeddingProvider.defaultModelID)
    XCTAssertFalse(decoded.hadAccessibilityGrant)
    XCTAssertEqual(decoded.userDisplayName, "")
    XCTAssertTrue(decoded.secureLocalModeEnabled)
    // Dictation dictionary absent -> empty replacements.
    XCTAssertTrue(decoded.dictationDictionary.replacements.isEmpty)
  }

  /// Round-trips the dictation dictionary (literal replacements) and confirms that an OLD
  /// settings.json still carrying the removed `spokenPunctuationEnabled` key decodes cleanly
  /// (the key is ignored) instead of failing.
  func testDictationDictionaryRoundTripAndMigration() throws {
    var settings = AppSettings()
    settings.dictationDictionary = DictationDictionary(
      replacements: [
        DictationReplacement(from: "notabene", to: "Notabene"),
        DictationReplacement(from: "ue", to: "ü", wholeWord: false),
      ]
    )

    let data = try makeEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded.dictationDictionary.replacements.count, 2)
    let first = try XCTUnwrap(decoded.dictationDictionary.replacements.first)
    XCTAssertEqual(first.from, "notabene")
    XCTAssertEqual(first.to, "Notabene")
    XCTAssertTrue(first.wholeWord)
    XCTAssertFalse(decoded.dictationDictionary.replacements[1].wholeWord)

    // Legacy settings WITH the now-removed punctuation key must still decode (key ignored).
    let legacyJSON = Data(
      #"{"dictationDictionary":{"replacements":[],"spokenPunctuationEnabled":true}}"#.utf8)
    let legacy = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
    XCTAssertTrue(legacy.dictationDictionary.replacements.isEmpty)
  }

  /// Round-trips the dictation-length cap and the silence-trimming opt-in.
  func testRoundTripPreservesDictationLengthAndSilenceTrimming() throws {
    var settings = AppSettings()
    settings.maxDictationMinutes = 60
    settings.silenceTrimmingEnabled = true

    let data = try makeEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    XCTAssertEqual(decoded.maxDictationMinutes, 60)
    XCTAssertTrue(decoded.silenceTrimmingEnabled)
  }

  /// An OLD settings.json missing the dictation keys must decode to the generous default length
  /// (so long dictations immediately work) and silence trimming OFF (conservative opt-in).
  func testMissingDictationKeysDecodeToSafeDefaults() throws {
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    XCTAssertEqual(decoded.maxDictationMinutes, AppSettings.defaultMaxDictationMinutes)
    XCTAssertFalse(decoded.silenceTrimmingEnabled)
  }

  /// A mode persisted WITHOUT the v2 `rewrite.useMemoryContext` key decodes to false.
  func testModeWithoutUseMemoryContextDefaultsFalse() throws {
    let json = """
      {
        "modes": {
          "textImprover": {
            "slot": "textImprover",
            "userName": "E-Mail",
            "isEnabled": true,
            "kind": "transcribeThenRewrite",
            "rewrite": {
              "systemPrompt": "x",
              "rewriteBackend": "openai",
              "modelID": "gpt-4o"
            }
          }
        }
      }
      """
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    let mode = try XCTUnwrap(decoded.modes["textImprover"])
    XCTAssertFalse(mode.rewrite.useMemoryContext)
    XCTAssertEqual(mode.rewrite.rewriteBackend, .openai)
    XCTAssertEqual(mode.userName, "E-Mail")
  }
}
