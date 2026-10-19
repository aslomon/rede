import XCTest

@testable import Rede

private final class RecordingProvider: RewriteProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var prompts: [String] = []
  var systemPrompts: [String] { lock.withLock { prompts } }

  func rewrite(
    systemPrompt: String, userText: String, temperature: Double
  ) async throws -> RewriteOutcome {
    lock.withLock { prompts.append(systemPrompt) }
    return RewriteOutcome(
      text: "Hallo zusammen 😀", usedModelID: "fixture", requestedModelID: "fixture")
  }
}

/// Social (the emoji kind) takes the same purpose overlay as the other rewriting modes, appended
/// AFTER the whole emoji prompt, so the mode's density and tone instructions stay in front.
final class EmojiRoutingOverlayTests: XCTestCase {
  private func run(
    purpose: DictationPurpose, density: EmojiTextSettings.EmojiDensity = .viel
  ) async throws -> (base: String, sent: [String]) {
    var rewrite = ModeConfig.default(for: .emojiText).rewrite
    rewrite.emojiDensity = density
    let provider = RecordingProvider()
    _ = try await WorkflowRewriteProcessor.emojiResult(
      cleanedRawText: "hallo zusammen wir treffen uns morgen", recordingDuration: 4,
      mode: .emojiText, backend: .remote, rewrite: rewrite, provider: provider,
      rewriteTerms: ["Anna"], purpose: purpose)
    let base = LLMService.emojiSystemPrompt(rewrite, customTerms: ["Anna"])
    return (base, provider.systemPrompts)
  }

  func testOtherPurposeSendsExactlyTheUnchangedEmojiPrompt() async throws {
    let (base, sent) = try await run(purpose: .other)
    XCTAssertEqual(sent, [base])
  }

  func testEmailAndPromptOverlaysFollowTheWholeEmojiPrompt() async throws {
    for purpose in [DictationPurpose.email, .aiPrompt] {
      let (base, sent) = try await run(purpose: purpose)
      let prompt = try XCTUnwrap(sent.first)
      XCTAssertTrue(prompt.hasPrefix(base), "the mode prompt must come first, unchanged")
      XCTAssertTrue(prompt.count > base.count, "\(purpose) must add an overlay")
      XCTAssertTrue(
        prompt.contains("Preserve the mode's tone and emoji settings"), "\(purpose)")
      XCTAssertTrue(prompt.contains("grosszuegig"), "the density instruction is kept")
    }
  }

  func testTheCustomTermsStayInsideTheBasePromptBeforeTheOverlay() async throws {
    let (_, sent) = try await run(purpose: .email)
    let prompt = try XCTUnwrap(sent.first)
    let terms = try XCTUnwrap(prompt.range(of: "Anna"))
    let overlay = try XCTUnwrap(prompt.range(of: "--- Purpose formatting ---"))
    XCTAssertTrue(terms.lowerBound < overlay.lowerBound)
  }
}
