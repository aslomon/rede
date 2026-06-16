import XCTest

@testable import Rede

final class EmailMemoryPromptTests: XCTestCase {
  func testSemanticEmailMemoryBlockUsesLightBudget() throws {
    let block = try XCTUnwrap(
      LLMService.semanticEmailMemoryBlock(makeContext(level: .light, count: 4))
    )
    XCTAssertTrue(block.contains("Beispiel 1"))
    XCTAssertFalse(block.contains("Beispiel 2"))
    XCTAssertTrue(block.contains("Übernimm keine Fakten"))
  }

  func testSemanticEmailMemoryBlockUsesMediumBudget() throws {
    let block = try XCTUnwrap(
      LLMService.semanticEmailMemoryBlock(makeContext(level: .medium, count: 4))
    )
    XCTAssertTrue(block.contains("Beispiel 1"))
    XCTAssertTrue(block.contains("Beispiel 2"))
    XCTAssertFalse(block.contains("Beispiel 3"))
  }

  func testSemanticEmailMemoryBlockUsesStrongBudget() throws {
    let block = try XCTUnwrap(
      LLMService.semanticEmailMemoryBlock(makeContext(level: .strong, count: 4))
    )
    XCTAssertTrue(block.contains("Beispiel 4"))
  }

  func testRewritePromptInjectsSemanticEmailMemoryAfterVocabulary() {
    let prompt = LLMService.rewriteSystemPrompt(
      RewriteConfig(),
      customTerms: ["Rinnert"],
      selection: nil,
      memory: MemoryContext(names: ["Jason"], terms: [], foreign: []),
      emailMemory: makeContext(level: .light, count: 1)
    )

    let vocabularyRange = prompt.range(of: "[Persönliches Vokabular")
    let emailRange = prompt.range(of: "[Ähnliche frühere E-Mails")
    XCTAssertNotNil(vocabularyRange)
    XCTAssertNotNil(emailRange)
    XCTAssertLessThan(vocabularyRange?.lowerBound ?? prompt.endIndex, emailRange?.lowerBound ?? prompt.startIndex)
  }

  func testRewritePromptInjectsUserIdentityPerspective() {
    let prompt = LLMService.rewriteSystemPrompt(
      RewriteConfig(),
      customTerms: [],
      selection: nil,
      memory: nil,
      userIdentity: UserIdentityContext(displayName: "Jason Rinnert")
    )

    XCTAssertTrue(prompt.contains("[Schreibperspektive]"))
    XCTAssertTrue(prompt.contains("Ich schreibe als: Jason Rinnert"))
    XCTAssertTrue(prompt.contains("Absenderperspektive"))
    XCTAssertTrue(prompt.contains("Erfinde keine Empfänger"))
  }

  private func makeContext(
    level: SemanticEmailEnrichmentLevel,
    count: Int
  ) -> EmailSemanticMemoryContext {
    EmailSemanticMemoryContext(
      matches: (0..<count).map { index in
        EmailMemoryMatch(
          record: EmailSemanticMemoryRecord(
            date: Date(),
            modeID: "textImprover",
            appBundleID: "com.example.mail",
            appName: "Mail",
            windowTitle: "Client \(index)",
            rawTranscript: "raw \(index)",
            finalText: "Finished email \(index)",
            embedding: [1, 0],
            embeddingModel: "fixture"
          ),
          score: 0.91 - Double(index) * 0.01
        )
      },
      level: level
    )
  }
}
