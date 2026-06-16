import AppKit
import XCTest

@testable import Rede

/// R2-FT-sound: the optional dictation earcons map to BUILT-IN macOS system sounds. These tests pin
/// the event→name mapping and verify each name actually resolves to a real system sound (so a typo'd
/// name can't silently ship as "no feedback"). No audio is played — `NSSound(named:)` only loads.
@MainActor
final class EarconPlayerTests: XCTestCase {

  func testEventsMapToDistinctSoundNames() {
    let names = Set(
      [EarconPlayer.Event.start, .done, .error].map { $0.systemSoundName })
    XCTAssertEqual(names.count, 3, "Each earcon should be audibly distinct")
  }

  func testEverySoundNameResolvesToARealSystemSound() {
    for event in [EarconPlayer.Event.start, .done, .error] {
      XCTAssertNotNil(
        NSSound(named: event.systemSoundName),
        "System sound '\(event.systemSoundName)' should exist")
    }
  }

  func testAppSettingsDefaultsSoundFeedbackOff() {
    XCTAssertFalse(AppSettings().soundFeedbackEnabled)
  }

  func testSoundFeedbackFlagSurvivesCodableRoundTrip() throws {
    var settings = AppSettings()
    settings.soundFeedbackEnabled = true
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertTrue(decoded.soundFeedbackEnabled)
  }

  func testMissingKeyDecodesToOff() throws {
    // An older settings.json without the key must default to off (silent), not crash.
    let json = Data("{\"hotkeyMode\":\"hold\"}".utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
    XCTAssertFalse(decoded.soundFeedbackEnabled)
  }

  // MARK: - Dismissed MEM-2b suggestions persist (R4-FT-dismiss-persist)

  func testDismissedSuggestionKeysDefaultEmpty() {
    XCTAssertTrue(AppSettings().dismissedImprovementSuggestionKeys.isEmpty)
  }

  func testDismissedSuggestionKeysSurviveCodableRoundTrip() throws {
    var settings = AppSettings()
    settings.dismissedImprovementSuggestionKeys = ["rinert→rinnert", "notaben→notabene"]
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(
      decoded.dismissedImprovementSuggestionKeys, settings.dismissedImprovementSuggestionKeys)
  }

  // MARK: - No-speech message is a shared constant (R4-DR-earcon-nospeech)

  func testNoSpeechMessageIsStableNonEmpty() {
    XCTAssertEqual(TranscriptionQualityService.noSpeechMessage, "Keine Aufnahme erkannt.")
  }
}
