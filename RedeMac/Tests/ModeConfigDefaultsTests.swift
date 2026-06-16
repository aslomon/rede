import XCTest

@testable import Rede

/// `ModeConfig.default(for:)` plus its building-block static helpers are the source of truth
/// for the four repurposed slots (Diktat / E-Mail / Prompt / Social) and their curated prompts.
/// The migration in AppState composes these helpers, so locking them down protects the migration.
final class ModeConfigDefaultsTests: XCTestCase {

  // MARK: - User-facing default names

  func testDefaultUserNames() {
    XCTAssertEqual(ModeConfig.defaultUserName(for: .transcription), "Diktat")
    XCTAssertEqual(ModeConfig.defaultUserName(for: .localTranscription), "Diktat (lokal)")
    XCTAssertEqual(ModeConfig.defaultUserName(for: .textImprover), "E-Mail")
    XCTAssertEqual(ModeConfig.defaultUserName(for: .dampfAblassen), "Prompt")
    XCTAssertEqual(ModeConfig.defaultUserName(for: .emojiText), "Social")
  }

  func testDefaultForSlotComposesNameKindAndRewrite() {
    let email = ModeConfig.default(for: .textImprover)
    XCTAssertEqual(email.slot, .textImprover)
    XCTAssertEqual(email.id, WorkflowType.textImprover.rawValue)
    XCTAssertEqual(email.userName, "E-Mail")
    XCTAssertTrue(email.isEnabled)
    XCTAssertEqual(email.kind, .transcribeThenRewrite)
  }

  func testCustomModeCanKeepStableIDIndependentFromRuntimeSlot() {
    var clientEmail = ModeConfig.default(for: .textImprover)
    clientEmail.modeID = "email-client-a"
    clientEmail.userName = "E-Mail Kunde A"

    XCTAssertEqual(clientEmail.id, "email-client-a")
    XCTAssertEqual(clientEmail.slot, .textImprover)
    XCTAssertEqual(clientEmail.kind, .transcribeThenRewrite)
    XCTAssertEqual(clientEmail.userName, "E-Mail Kunde A")
  }

  func testDuplicateModePreservesBehaviorButGetsNewIdentityAndName() {
    var source = ModeConfig.default(for: .textImprover)
    source.modeID = "email"
    source.userName = "E-Mail"
    source.rewrite.context = "Existing client context"

    let duplicate = ModeConfig.duplicate(
      source,
      newID: "email-client-a",
      userName: "E-Mail Kunde A"
    )

    XCTAssertEqual(duplicate.id, "email-client-a")
    XCTAssertEqual(duplicate.slot, .textImprover)
    XCTAssertEqual(duplicate.kind, source.kind)
    XCTAssertEqual(duplicate.rewrite.context, "Existing client context")
    XCTAssertEqual(duplicate.userName, "E-Mail Kunde A")
  }

  // MARK: - Default kinds

  func testDefaultKinds() {
    XCTAssertEqual(ModeConfig.defaultKind(for: .transcription), .transcribeOnly)
    XCTAssertEqual(ModeConfig.defaultKind(for: .localTranscription), .transcribeOnly)
    XCTAssertEqual(ModeConfig.defaultKind(for: .textImprover), .transcribeThenRewrite)
    XCTAssertEqual(ModeConfig.defaultKind(for: .dampfAblassen), .transcribeThenRewrite)
    XCTAssertEqual(ModeConfig.defaultKind(for: .emojiText), .transcribeThenEmoji)
  }

  // MARK: - Curated prompts

  func testEmailSlotUsesCuratedEmailPrompt() {
    let email = ModeConfig.default(for: .textImprover)
    XCTAssertEqual(email.rewrite.systemPrompt, ModeDefaults.emailSystemPrompt)
    XCTAssertEqual(email.rewrite.modelID, RewriteModelRegistry.strongModelID)
    XCTAssertTrue(email.rewrite.systemPrompt.contains("email"))
    XCTAssertTrue(email.rewrite.useAutomaticFieldContext)
    XCTAssertTrue(email.rewrite.useMemoryContext)
    XCTAssertTrue(email.rewrite.useSemanticEmailMemory)
  }

  func testPromptSlotUsesCuratedPromptCraftPrompt() {
    let prompt = ModeConfig.default(for: .dampfAblassen)
    XCTAssertEqual(prompt.rewrite.systemPrompt, ModeDefaults.promptCraftSystemPrompt)
    XCTAssertEqual(prompt.rewrite.modelID, RewriteModelRegistry.strongModelID)
    XCTAssertTrue(prompt.rewrite.systemPrompt.contains("Claude Code"))
    XCTAssertTrue(prompt.rewrite.useAutomaticFieldContext)
    XCTAssertTrue(prompt.rewrite.useMemoryContext)
    XCTAssertFalse(prompt.rewrite.useSemanticEmailMemory)
  }

  func testEmojiSlotUsesFastModelAndNoSystemPrompt() {
    let social = ModeConfig.default(for: .emojiText)
    XCTAssertEqual(social.kind, .transcribeThenEmoji)
    XCTAssertEqual(social.rewrite.modelID, RewriteModelRegistry.fastModelID)
    XCTAssertTrue(social.rewrite.systemPrompt.isEmpty)
  }

  func testTranscriptionSlotsHaveEmptyRewrite() {
    let plain = ModeConfig.default(for: .transcription)
    XCTAssertTrue(plain.rewrite.systemPrompt.isEmpty)
    XCTAssertEqual(plain.rewrite.rewriteBackend, .openai)
    XCTAssertEqual(plain.kind, .transcribeOnly)
  }

  // MARK: - Curated prompt content integrity (structured multi-line markdown prompts)

  func testCuratedPromptsAreSubstantialMarkdownAndClean() {
    // The curated prompts are now structured markdown (headed sections), not single-line paragraphs.
    // Assert they are substantial, use markdown headings, and carry no stray double spaces.
    for prompt in [ModeDefaults.emailSystemPrompt, ModeDefaults.promptCraftSystemPrompt] {
      XCTAssertGreaterThan(prompt.count, 400)
      XCTAssertTrue(prompt.contains("# "))
      XCTAssertFalse(prompt.contains("  "))  // no double spaces inside the lines
    }
  }

  func testLegacyPromptsDifferFromCurrent() {
    // The migration relies on the OLD defaults being distinct from the new ones.
    XCTAssertNotEqual(ModeDefaults.legacyEmailSystemPrompt, ModeDefaults.emailSystemPrompt)
    XCTAssertNotEqual(
      ModeDefaults.legacyPromptCraftSystemPrompt, ModeDefaults.promptCraftSystemPrompt)
  }

  func testSemanticEmailMemorySettingsRoundTrip() throws {
    var config = ModeConfig.default(for: .textImprover)
    config.rewrite.semanticEmailEnrichmentLevel = .strong

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(ModeConfig.self, from: data)

    XCTAssertTrue(decoded.rewrite.useSemanticEmailMemory)
    XCTAssertEqual(decoded.rewrite.semanticEmailEnrichmentLevel, .strong)
    XCTAssertTrue(decoded.isAdvancedNonDefault)
  }

  func testTwoVariantSettingRoundTrip() throws {
    var config = ModeConfig.default(for: .textImprover)
    config.rewrite.showTwoVariants = true

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(ModeConfig.self, from: data)

    XCTAssertTrue(decoded.rewrite.showTwoVariants)
    XCTAssertTrue(decoded.isAdvancedNonDefault)
  }
}
