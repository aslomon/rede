import XCTest

@testable import Blitztext

/// `FuzzyTermCorrector` snaps a CLEAR near-miss of a known term to its canonical spelling, but must
/// stay CONSERVATIVE — a false positive corrupts the user's text. These tests pin BOTH the
/// corrections it should make AND, crucially, the ones it must NOT.
final class FuzzyTermCorrectorTests: XCTestCase {

  // MARK: - Corrections it SHOULD make

  func testCorrectsNearMissProperNoun() {
    XCTAssertEqual(
      FuzzyTermCorrector.correct("Frag mal Rinert dazu", terms: ["Rinnert"]),
      "Frag mal Rinnert dazu")
  }

  func testCorrectsMissingLetter() {
    XCTAssertEqual(
      FuzzyTermCorrector.correct("Öffne Blitztex bitte", terms: ["Blitztext"]),
      "Öffne Blitztext bitte")
  }

  func testAppliesCanonicalCasingOnNearMiss() {
    // A near-miss (not exact) is snapped to the term's own casing.
    XCTAssertEqual(FuzzyTermCorrector.correct("rinert", terms: ["Rinnert"]), "Rinnert")
  }

  func testPreservesSurroundingPunctuation() {
    XCTAssertEqual(
      FuzzyTermCorrector.correct("„Rinert\", sagte er", terms: ["Rinnert"]),
      "„Rinnert\", sagte er")
  }

  // MARK: - Corrections it must NOT make

  func testExactMatchIsLeftVerbatim() {
    // Case-insensitive exact match → no re-casing, no change.
    XCTAssertEqual(FuzzyTermCorrector.correct("rinnert", terms: ["Rinnert"]), "rinnert")
    XCTAssertEqual(FuzzyTermCorrector.correct("Rinnert", terms: ["Rinnert"]), "Rinnert")
  }

  func testDoesNotCorrectUnrelatedWord() {
    XCTAssertEqual(
      FuzzyTermCorrector.correct("Der Garten ist schön", terms: ["Rinnert"]),
      "Der Garten ist schön")
  }

  func testDoesNotCorrectAmbiguousNearMiss() {
    // "Mabel" is edit-distance 1 from BOTH terms → ambiguous → left untouched.
    XCTAssertEqual(
      FuzzyTermCorrector.correct("Mabel", terms: ["Kabel", "Nabel"]),
      "Mabel")
  }

  func testShortTermsNeverTrigger() {
    // Terms shorter than 4 chars are excluded (too many spurious near-misses).
    XCTAssertEqual(FuzzyTermCorrector.correct("Tat", terms: ["Tag"]), "Tat")
  }

  func testEmptyTermsIsNoOp() {
    XCTAssertEqual(FuzzyTermCorrector.correct("foo bar baz", terms: []), "foo bar baz")
  }

  func testLeavesCleanSentenceUnchanged() {
    XCTAssertEqual(
      FuzzyTermCorrector.correct("Das ist der wichtigste Punkt", terms: ["Rinnert", "Blitztext"]),
      "Das ist der wichtigste Punkt")
  }
}
