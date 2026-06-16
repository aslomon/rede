import XCTest

@testable import Rede

/// B6 — making the EFFECTIVE rewrite model visible. The live provider call needs a network round
/// trip and a Keychain key, so it isn't unit-testable. These tests pin the PURE logic the UI relies
/// on: the `RewriteOutcome` struct's fallback detection and the German note built from
/// (requested, used) by `RewriteModelRegistry.fallbackNote`.
final class RewriteOutcomeTests: XCTestCase {

  // MARK: - RewriteOutcome.didFallBack

  func testHappyPathUsedEqualsRequestedIsNotAFallback() {
    let outcome = RewriteOutcome(text: "Hallo", usedModelID: "gpt-5.4", requestedModelID: "gpt-5.4")
    XCTAssertFalse(outcome.didFallBack)
  }

  func testDifferentUsedModelIsAFallback() {
    let outcome = RewriteOutcome(
      text: "Hallo", usedModelID: "gpt-4o-mini", requestedModelID: "gpt-5.4")
    XCTAssertTrue(outcome.didFallBack)
  }

  func testMissingModelIDsNeverCountAsFallback() {
    let onlyUsed = RewriteOutcome(text: "x", usedModelID: "gpt-4o", requestedModelID: nil)
    let onlyRequested = RewriteOutcome(text: "x", usedModelID: nil, requestedModelID: "gpt-4o")
    let neither = RewriteOutcome(text: "x", usedModelID: nil, requestedModelID: nil)
    XCTAssertFalse(onlyUsed.didFallBack)
    XCTAssertFalse(onlyRequested.didFallBack)
    XCTAssertFalse(neither.didFallBack)
  }

  func testOutcomeDefaultsVariantsToPrimaryText() {
    let outcome = RewriteOutcome(text: "Primary", usedModelID: "gpt-5.4", requestedModelID: "gpt-5.4")
    XCTAssertEqual(outcome.variants, ["Primary"])
  }

  func testOutcomePreservesExplicitVariants() {
    let outcome = RewriteOutcome(
      text: "A",
      variants: ["A", "B"],
      usedModelID: "gpt-5.4",
      requestedModelID: "gpt-5.4"
    )
    XCTAssertEqual(outcome.variants, ["A", "B"])
  }

  // MARK: - RewriteModelRegistry.fallbackNote (the user-facing note)

  func testNoNoteOnTheHappyPath() {
    XCTAssertNil(RewriteModelRegistry.fallbackNote(requested: "gpt-5.4", used: "gpt-5.4"))
  }

  func testNoNoteWhenEitherModelIsMissing() {
    XCTAssertNil(RewriteModelRegistry.fallbackNote(requested: nil, used: "gpt-4o-mini"))
    XCTAssertNil(RewriteModelRegistry.fallbackNote(requested: "gpt-5.4", used: nil))
    XCTAssertNil(RewriteModelRegistry.fallbackNote(requested: nil, used: nil))
  }

  func testFallbackNoteIsBuiltFromCuratedLabelsInGerman() {
    let note = RewriteModelRegistry.fallbackNote(requested: "gpt-5.4", used: "gpt-4o-mini")
    // Uses the friendly curated labels, not the raw ids, and reads in German du-form.
    XCTAssertEqual(note, "Modell GPT-5.4 nicht verfügbar — GPT-4o mini verwendet.")
  }

  /// The default real-world case: chosen strong model rejected → universal safe fallback.
  func testDefaultStrongToSafeFallbackProducesTheNote() {
    let note = RewriteModelRegistry.fallbackNote(
      requested: RewriteModelRegistry.strongModelID,
      used: RewriteModelRegistry.safeFallbackModelID
    )
    XCTAssertNotNil(note)
    XCTAssertTrue(note?.contains("nicht verfügbar") ?? false)
  }

  /// Unknown account ids fall through to their raw id as the label — still a single readable line.
  func testUnknownModelIDsFallBackToRawIDInTheNote() {
    let note = RewriteModelRegistry.fallbackNote(requested: "acme-x", used: "gpt-4o-mini")
    XCTAssertEqual(note, "Modell acme-x nicht verfügbar — GPT-4o mini verwendet.")
  }
}
