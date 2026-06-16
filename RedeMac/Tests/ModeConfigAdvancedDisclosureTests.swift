import XCTest

@testable import Rede

/// `ModeConfig.isAdvancedNonDefault` decides whether the collapsed "Erweitert" disclosure in
/// `ModeCardView` shows an "angepasst" dot. It is pure (no SwiftUI / AppState), so it is locked
/// down here against the curated slot defaults.
final class ModeConfigAdvancedDisclosureTests: XCTestCase {

  // MARK: - Defaults are NOT flagged as customized

  func testDefaultEmailModeIsNotFlagged() {
    // The E-Mail slot ships with a curated system prompt; that curated default must NOT count as
    // a user customization, otherwise every fresh install would show the "angepasst" dot.
    XCTAssertFalse(ModeConfig.default(for: .textImprover).isAdvancedNonDefault)
  }

  func testDefaultPromptModeIsNotFlagged() {
    XCTAssertFalse(ModeConfig.default(for: .dampfAblassen).isAdvancedNonDefault)
  }

  func testDefaultEmojiModeIsNotFlagged() {
    XCTAssertFalse(ModeConfig.default(for: .emojiText).isAdvancedNonDefault)
  }

  func testDefaultTranscriptionModeIsNotFlagged() {
    XCTAssertFalse(ModeConfig.default(for: .transcription).isAdvancedNonDefault)
  }

  // MARK: - A custom system prompt flags the mode

  func testCustomSystemPromptFlagsEmojiMode() {
    // Emoji ships with an empty prompt, so any non-empty prompt is a deviation.
    var social = ModeConfig.default(for: .emojiText)
    social.rewrite.systemPrompt = "Mach es lustig."
    XCTAssertTrue(social.isAdvancedNonDefault)
  }

  func testClearedSystemPromptUnflagsEmailModeAtTone() {
    // If the user wipes the curated E-Mail prompt but leaves everything else at default,
    // there is no longer a custom prompt and no other deviation → not flagged.
    var email = ModeConfig.default(for: .textImprover)
    email.rewrite.systemPrompt = ""
    XCTAssertFalse(email.isAdvancedNonDefault)
  }

  // MARK: - Tone / context / reply / memory deviations flag the mode

  func testChangedToneFlagsEmojiMode() {
    var social = ModeConfig.default(for: .emojiText)
    social.rewrite.tone = .formal
    XCTAssertTrue(social.isAdvancedNonDefault)
  }

  func testChangedContextFlagsEmojiMode() {
    var social = ModeConfig.default(for: .emojiText)
    social.rewrite.context = "Marketing"
    XCTAssertTrue(social.isAdvancedNonDefault)
  }

  func testChangedReplyContextFlagsEmojiMode() {
    var social = ModeConfig.default(for: .emojiText)
    social.rewrite.replyContextMode = .replyUsingContext
    XCTAssertTrue(social.isAdvancedNonDefault)
  }

  func testEnabledMemoryContextFlagsEmojiMode() {
    var social = ModeConfig.default(for: .emojiText)
    social.rewrite.useMemoryContext = true
    XCTAssertTrue(social.isAdvancedNonDefault)
  }
}
