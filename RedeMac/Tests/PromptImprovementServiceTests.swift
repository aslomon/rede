import XCTest

@testable import Rede

final class PromptImprovementServiceTests: XCTestCase {
  func testCleanedOutputRemovesCodeFenceAndLanguageTag() {
    let output = PromptImprovementService.cleanedOutput(
      """
      ```markdown
      # Role

      Improve the text.
      ```
      """
    )

    XCTAssertEqual(output, "# Role\n\nImprove the text.")
  }

  func testImprovementPromptRequiresPromptOnlyOutput() {
    XCTAssertTrue(PromptImprovementService.systemPrompt.contains("Return only the improved system prompt"))
    XCTAssertTrue(PromptImprovementService.systemPrompt.contains("no code fence"))
  }
}
