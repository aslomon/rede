import XCTest

@testable import Rede

/// `AppState.effectiveRewriteTerms` feeds the chat-LLM rewrite prompt, which has no Whisper
/// 224-token budget — so unlike `effectiveCustomTerms` it must NOT cap+reverse. These tests pin
/// the pure merge helper that backs it: user terms first, memory terms after, natural order, no
/// reversal, generous cap, deduped + trimmed.
final class RewriteTermsMergeTests: XCTestCase {

  // MARK: - Ordering: user terms first, then memory terms, natural (most-important-first)

  func testUserTermsComeFirstThenMemoryTermsInNaturalOrder() {
    let merged = AppState.mergedTerms(
      userTerms: ["Rinnert", "Notabene"],
      memoryTerms: ["Kubernetes", "Deadline"]
    )
    XCTAssertEqual(merged, ["Rinnert", "Notabene", "Kubernetes", "Deadline"])
  }

  /// Unlike the Whisper hint, the rewrite list is NOT reversed — best terms stay FIRST.
  func testOrderIsNotReversed() {
    let merged = AppState.mergedTerms(userTerms: ["A", "B", "C"], memoryTerms: [])
    XCTAssertEqual(merged, ["A", "B", "C"])
  }

  // MARK: - No tight cap (only the generous safety bound applies)

  func testNoWhisperCapManyTermsSurvive() {
    // Far more than the Whisper injectionCap (55) — all must survive for the rewrite prompt.
    let userTerms = (0..<120).map { "User\($0)" }
    let merged = AppState.mergedTerms(userTerms: userTerms, memoryTerms: [])
    XCTAssertEqual(merged.count, 120)
    XCTAssertGreaterThan(merged.count, MemoryStore.injectionCap)
  }

  func testGenerousCapIsRespected() {
    let userTerms = (0..<300).map { "User\($0)" }
    let merged = AppState.mergedTerms(userTerms: userTerms, memoryTerms: [])
    // The helper itself is uncapped; the computed var applies rewriteTermsCap.
    let capped = Array(merged.prefix(AppState.rewriteTermsCap))
    XCTAssertEqual(capped.count, AppState.rewriteTermsCap)
    XCTAssertEqual(AppState.rewriteTermsCap, 200)
  }

  // MARK: - Dedup + trim

  func testDeduplicatesCaseInsensitivelyKeepingFirstOccurrence() {
    let merged = AppState.mergedTerms(
      userTerms: ["Kubernetes", "kubernetes"],
      memoryTerms: ["KUBERNETES", "Deadline"]
    )
    XCTAssertEqual(merged, ["Kubernetes", "Deadline"])
  }

  func testTrimsWhitespaceAndDropsEmpty() {
    let merged = AppState.mergedTerms(
      userTerms: ["  Rinnert  ", "   ", ""],
      memoryTerms: [" Deadline "]
    )
    XCTAssertEqual(merged, ["Rinnert", "Deadline"])
  }

  func testEmptyInputsProduceEmptyResult() {
    XCTAssertTrue(AppState.mergedTerms(userTerms: [], memoryTerms: []).isEmpty)
  }
}
