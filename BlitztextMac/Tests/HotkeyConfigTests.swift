import XCTest

@testable import Blitztext

final class HotkeyConfigTests: XCTestCase {

  func testLegacyDefaultLabelsMatchCurrentHotkeys() {
    XCTAssertEqual(
      HotkeyRegistry.defaultConfig(modeID: "transcription", slot: .transcription).label,
      "fn + Shift"
    )
    XCTAssertEqual(
      HotkeyRegistry.defaultConfig(modeID: "localTranscription", slot: .localTranscription).label,
      "fn + Shift + Ctrl"
    )
    XCTAssertEqual(
      HotkeyRegistry.defaultConfig(modeID: "textImprover", slot: .textImprover).label,
      "fn + Ctrl"
    )
    XCTAssertEqual(
      HotkeyRegistry.defaultConfig(modeID: "dampfAblassen", slot: .dampfAblassen).label,
      "fn + Option"
    )
    XCTAssertEqual(
      HotkeyRegistry.defaultConfig(modeID: "emojiText", slot: .emojiText).label,
      "fn + Cmd"
    )
  }

  func testDynamicDuplicateModeDefaultsToNoShortcut() {
    var duplicateEmail = ModeConfig.default(for: .textImprover)
    duplicateEmail.modeID = "email-client-a"

    let configs = HotkeyRegistry.effectiveConfigs(
      for: [duplicateEmail],
      stored: [:]
    )

    XCTAssertEqual(configs["email-client-a"]?.label, "nicht gesetzt")
    XCTAssertFalse(configs["email-client-a"]?.isEnabled ?? true)
  }

  func testStoredDynamicHotkeySurvivesAppSettingsRoundTrip() throws {
    var settings = AppSettings()
    settings.hotkeys = [
      "email-client-a": HotkeyConfig(
        modeID: "email-client-a",
        modifiers: [.function, .option, .shift],
        keyCode: 8,
        keyLabel: "C",
        isEnabled: true
      )
    ]

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    XCTAssertEqual(decoded.hotkeys["email-client-a"]?.label, "fn + Shift + Option + C")
    XCTAssertEqual(decoded.hotkeys["email-client-a"]?.keyCode, 8)
    XCTAssertTrue(decoded.hotkeys["email-client-a"]?.isEnabled ?? false)
  }

  func testMatchingFindsModeForExactModifierSetOnlyWhenNoKeyIsSet() {
    let config = HotkeyConfig(
      modeID: "email-client-a",
      modifiers: [.function, .option, .shift],
      isEnabled: true
    )

    XCTAssertEqual(
      HotkeyRegistry.matchingModeID(
        modifiers: [.function, .option, .shift],
        keyCode: nil,
        configs: ["email-client-a": config]
      ),
      "email-client-a"
    )
    XCTAssertNil(
      HotkeyRegistry.matchingModeID(
        modifiers: [.function, .option],
        keyCode: nil,
        configs: ["email-client-a": config]
      )
    )
  }

  func testMatchingFindsPlainSingleKeyHotkey() {
    let config = HotkeyConfig(
      modeID: "free-text",
      modifiers: [],
      keyCode: 49,
      keyLabel: "Space",
      isEnabled: true
    )

    XCTAssertEqual(
      HotkeyRegistry.matchingModeID(
        modifiers: [],
        keyCode: 49,
        configs: ["free-text": config]
      ),
      "free-text"
    )
    XCTAssertNil(
      HotkeyRegistry.matchingModeID(
        modifiers: [.command],
        keyCode: 49,
        configs: ["free-text": config]
      )
    )
  }

  func testMatchingFindsModifierPlusKeyHotkey() {
    let config = HotkeyConfig(
      modeID: "prompt",
      modifiers: [.command, .shift],
      keyCode: 35,
      keyLabel: "P",
      isEnabled: true
    )

    XCTAssertEqual(
      HotkeyRegistry.matchingModeID(
        modifiers: [.shift, .command],
        keyCode: 35,
        configs: ["prompt": config]
      ),
      "prompt"
    )
  }

  func testStoredDynamicHotkeySupportsMultipleRegularKeys() throws {
    var settings = AppSettings()
    settings.hotkeys = [
      "research": HotkeyConfig(
        modeID: "research",
        modifiers: [.command],
        keys: [
          HotkeyKeyBinding(keyCode: 38, keyLabel: "J"),
          HotkeyKeyBinding(keyCode: 40, keyLabel: "K"),
        ],
        isEnabled: true
      )
    ]

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    XCTAssertEqual(decoded.hotkeys["research"]?.label, "Cmd + J + K")
    XCTAssertEqual(decoded.hotkeys["research"]?.normalizedKeys.map(\.keyCode), [38, 40])
  }

  func testMatchingFindsExactMultiKeyHotkey() {
    let config = HotkeyConfig(
      modeID: "research",
      modifiers: [.command],
      keys: [
        HotkeyKeyBinding(keyCode: 38, keyLabel: "J"),
        HotkeyKeyBinding(keyCode: 40, keyLabel: "K"),
      ],
      isEnabled: true
    )

    XCTAssertEqual(
      HotkeyRegistry.matchingModeID(
        modifiers: [.command],
        keyCodes: [40, 38],
        configs: ["research": config]
      ),
      "research"
    )
    XCTAssertNil(
      HotkeyRegistry.matchingModeID(
        modifiers: [.command],
        keyCodes: [38],
        configs: ["research": config]
      )
    )
  }

  func testPotentialMatchFindsPartialMultiKeyPrefix() {
    let config = HotkeyConfig(
      modeID: "research",
      modifiers: [.command],
      keys: [
        HotkeyKeyBinding(keyCode: 38, keyLabel: "J"),
        HotkeyKeyBinding(keyCode: 40, keyLabel: "K"),
      ],
      isEnabled: true
    )

    XCTAssertTrue(
      HotkeyRegistry.hasPotentialMatch(
        modifiers: [.command],
        keyCodes: [38],
        configs: ["research": config]
      )
    )
    XCTAssertFalse(
      HotkeyRegistry.hasPotentialMatch(
        modifiers: [.option],
        keyCodes: [38],
        configs: ["research": config]
      )
    )
  }

  func testDuplicateValidationReportsConflictingEnabledShortcuts() {
    let issues = HotkeyRegistry.validationIssues(
      configs: [
        "email-a": HotkeyConfig(modeID: "email-a", modifiers: [.function, .control]),
        "email-b": HotkeyConfig(modeID: "email-b", modifiers: [.function, .control]),
      ]
    )

    XCTAssertEqual(issues, [.duplicate(label: "fn + Ctrl", modeIDs: ["email-a", "email-b"])])
  }

  func testDuplicateValidationSeparatesSameModifiersWithDifferentKeys() {
    let issues = HotkeyRegistry.validationIssues(
      configs: [
        "prompt": HotkeyConfig(
          modeID: "prompt",
          modifiers: [.command],
          keyCode: 35,
          keyLabel: "P"),
        "post": HotkeyConfig(
          modeID: "post",
          modifiers: [.command],
          keyCode: 31,
          keyLabel: "O"),
      ]
    )

    XCTAssertTrue(issues.isEmpty)
  }

  func testCandidateConflictIgnoresCurrentModeButBlocksOtherMode() {
    let current = HotkeyConfig(
      modeID: "email",
      modifiers: [.command],
      keys: [HotkeyKeyBinding(keyCode: 38, keyLabel: "J")]
    )
    let other = HotkeyConfig(
      modeID: "prompt",
      modifiers: [.command],
      keys: [HotkeyKeyBinding(keyCode: 40, keyLabel: "K")]
    )

    XCTAssertNil(
      HotkeyRegistry.conflictLabel(
        for: current,
        excluding: "email",
        configs: ["email": current, "prompt": other]
      )
    )
    XCTAssertEqual(
      HotkeyRegistry.conflictLabel(
        for: current,
        excluding: "new-mode",
        configs: ["email": current, "prompt": other]
      ),
      "konflikt: Cmd + J ist bereits belegt."
    )
  }

  func testModeTemplateCreatesExpectedSlots() {
    XCTAssertEqual(ModeTemplate.freeText.makeMode(id: "free").slot, .transcription)
    XCTAssertEqual(ModeTemplate.email.makeMode(id: "email").slot, .textImprover)
    XCTAssertEqual(ModeTemplate.prompt.makeMode(id: "prompt").slot, .dampfAblassen)
    XCTAssertEqual(ModeTemplate.social.makeMode(id: "social").slot, .emojiText)
  }
}
