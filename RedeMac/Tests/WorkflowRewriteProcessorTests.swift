import XCTest

@testable import Rede

final class WorkflowRewriteProcessorTests: XCTestCase {
  func testSecondVariantPromptRejectsSmallWordSwaps() {
    let prompt = RewriteVariantBuilder.secondVariantPrompt("Basis")

    XCTAssertTrue(prompt.contains("klar alternative Version"))
    XCTAssertTrue(prompt.contains("nicht dieselbe Version"))
  }

  actor RewriteCallLog {
    private var values: [Date] = []

    func recordStart() {
      values.append(Date())
    }

    func starts() -> [Date] {
      values
    }
  }

  struct DelayedVariantProvider: RewriteProvider {
    let log: RewriteCallLog
    let delayNanoseconds: UInt64
    let failSecondVariant: Bool

    func rewrite(systemPrompt: String, userText _: String, temperature _: Double) async throws
      -> RewriteOutcome
    {
      await log.recordStart()
      try await Task.sleep(nanoseconds: delayNanoseconds)
      let isSecond = systemPrompt.contains("zweite, klar alternative Version")
      if isSecond, failSecondVariant {
        throw LLMError.noContent
      }
      return RewriteOutcome(
        text: isSecond ? "zweite version" : "erste version",
        usedModelID: "test-model",
        requestedModelID: "test-model"
      )
    }
  }

  func testOnlineTwoVariantRewriteStartsRequestsConcurrently() async throws {
    let log = RewriteCallLog()
    let provider = DelayedVariantProvider(
      log: log,
      delayNanoseconds: 150_000_000,
      failSecondVariant: false
    )

    let result = try await WorkflowRewriteProcessor.emojiResult(
      cleanedRawText: "hallo",
      recordingDuration: 1,
      mode: .emojiText,
      backend: .remote,
      rewrite: RewriteConfig(systemPrompt: "emoji", showTwoVariants: true),
      provider: provider,
      rewriteTerms: []
    )

    guard case .variants(let pending, _) = result else {
      return XCTFail("Expected variants")
    }
    let starts = await log.starts()
    XCTAssertEqual(pending.variants.map(\.text), ["erste version", "zweite version"])
    XCTAssertEqual(starts.count, 2)
    XCTAssertLessThan(abs(starts[1].timeIntervalSince(starts[0])), 0.1)
  }

  func testSecondVariantFailureFallsBackToFirstRewrite() async throws {
    let provider = DelayedVariantProvider(
      log: RewriteCallLog(),
      delayNanoseconds: 1_000_000,
      failSecondVariant: true
    )

    let result = try await WorkflowRewriteProcessor.emojiResult(
      cleanedRawText: "hallo",
      recordingDuration: 1,
      mode: .emojiText,
      backend: .remote,
      rewrite: RewriteConfig(systemPrompt: "emoji", showTwoVariants: true),
      provider: provider,
      rewriteTerms: []
    )

    guard case .completed(_, let finalText, _) = result else {
      return XCTFail("Expected one-variant fallback")
    }
    XCTAssertEqual(finalText, "erste version")
  }
}
