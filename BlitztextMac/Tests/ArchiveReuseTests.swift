import AppKit
import XCTest

@testable import Blitztext

/// FT-3 "Archiv wiederverwenden": pure, provider-free parts of re-running a rewrite on a stored
/// transcript. The async `AppState.rerunRewrite` needs a live OpenAI/Ollama backend, so we pin the
/// eligibility list, the per-mode prompt selection, the concealed clipboard copy and the pre-flight
/// error copy instead — everything the UI relies on before a network call ever happens.
final class ArchiveReuseTests: XCTestCase {

  // MARK: - Rewrite-capable mode list (the Menu's contents)

  func testRewriteCapableModesAreExactlyTheThreeRewriteSlots() {
    XCTAssertEqual(
      WorkflowType.rewriteCapableModes,
      [.textImprover, .dampfAblassen, .emojiText]
    )
  }

  func testPlainTranscriptionModesAreNotRewriteCapable() {
    XCTAssertFalse(WorkflowType.transcription.isRewriteCapable)
    XCTAssertFalse(WorkflowType.localTranscription.isRewriteCapable)
  }

  func testRewriteSlotsAreRewriteCapable() {
    XCTAssertTrue(WorkflowType.textImprover.isRewriteCapable)
    XCTAssertTrue(WorkflowType.dampfAblassen.isRewriteCapable)
    XCTAssertTrue(WorkflowType.emojiText.isRewriteCapable)
  }

  func testRewriteCapableModesAllHaveADisplayNameAndAreUnique() {
    let names = WorkflowType.rewriteCapableModes.map { ModeConfig.defaultUserName(for: $0) }
    XCTAssertEqual(Set(names).count, names.count)
    XCTAssertFalse(names.contains(where: \.isEmpty))
  }

  // MARK: - Prompt selection mirrors the live workflows

  func testEmojiSlotUsesEmojiPromptNotTheImproverPrompt() {
    let rewrite = ModeConfig.default(for: .emojiText).rewrite
    let prompt = RewriteReuse.systemPrompt(
      kind: .transcribeThenEmoji, rewrite: rewrite, customTerms: [], memory: nil)
    XCTAssertEqual(prompt, LLMService.emojiSystemPrompt(rewrite, customTerms: []))
    // Emoji prompt talks about emojis; the improver prompt talks about "Lektor".
    XCTAssertTrue(prompt.lowercased().contains("emoji"))
    XCTAssertFalse(prompt.contains("Lektor"))
  }

  func testRewriteSlotUsesImproverPromptWithNilSelection() {
    let rewrite = ModeConfig.default(for: .textImprover).rewrite
    let prompt = RewriteReuse.systemPrompt(
      kind: .transcribeThenRewrite, rewrite: rewrite, customTerms: [], memory: nil)
    XCTAssertEqual(
      prompt,
      LLMService.rewriteSystemPrompt(rewrite, customTerms: [], selection: nil, memory: nil))
    // The curated email prompt carries through.
    XCTAssertTrue(prompt.contains("email"))
  }

  func testCustomTermsFlowIntoTheRerunPrompt() {
    let rewrite = RewriteConfig(systemPrompt: "Schreibe sauber.")
    let prompt = RewriteReuse.systemPrompt(
      kind: .transcribeThenRewrite, rewrite: rewrite, customTerms: ["Rinnert"], memory: nil)
    XCTAssertTrue(prompt.contains("Rinnert"))
  }

  // MARK: - Pre-flight error copy (surfaced in the row when a backend isn't ready)

  func testRerunErrorDescriptionsAreGuiding() {
    XCTAssertNotNil(AppState.RerunError.emptyTranscript.errorDescription)
    XCTAssertTrue(
      AppState.RerunError.backendNotReady(.openai).errorDescription?.contains("API Key") ?? false)
    XCTAssertTrue(
      AppState.RerunError.backendNotReady(.local).errorDescription?.contains("Ollama") ?? false)
  }

  // MARK: - Concealed clipboard copy

  func testCopyConcealedWritesStringAndConcealedMarker() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ArchiveReuseTestsPasteboard"))
    ArchiveClipboard.copyConcealed("Hallo Welt", pasteboard: pasteboard)
    XCTAssertEqual(pasteboard.string(forType: .string), "Hallo Welt")
    XCTAssertNotNil(pasteboard.types?.contains(ArchiveClipboard.concealedType))
    XCTAssertTrue(pasteboard.types?.contains(ArchiveClipboard.concealedType) ?? false)
  }

  func testCopyConcealedIgnoresEmptyText() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ArchiveReuseTestsEmptyPasteboard"))
    pasteboard.clearContents()
    pasteboard.declareTypes([.string], owner: nil)
    pasteboard.setString("vorher", forType: .string)
    ArchiveClipboard.copyConcealed("", pasteboard: pasteboard)
    // Empty input is a no-op, so the prior contents survive untouched.
    XCTAssertEqual(pasteboard.string(forType: .string), "vorher")
  }
}
