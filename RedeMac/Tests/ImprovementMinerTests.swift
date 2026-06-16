import XCTest

@testable import Rede

/// MEM-2b `ImprovementMiner` turns recorded before→after corrections into confirmable dictionary
/// suggestions. It must be CONSERVATIVE: only a recurring, clean single-word change becomes a
/// suggestion — multi-word edits, punctuation-only diffs, one-offs and dictionary duplicates must
/// not. These tests pin both what it suggests and (crucially) what it must not.
final class ImprovementMinerTests: XCTestCase {

  // MARK: - Suggests recurring single-word fixes

  func testRecurringSingleWordChangeBecomesSuggestion() {
    let observations = [
      changed("Frag mal Rinert dazu", "Frag mal Rinnert dazu"),
      changed("Hallo Rinert wie gehts", "Hallo Rinnert wie gehts"),
    ]
    let suggestions = ImprovementMiner.suggestions(from: observations)
    XCTAssertEqual(suggestions.count, 1)
    XCTAssertEqual(suggestions.first?.from, "Rinert")
    XCTAssertEqual(suggestions.first?.to, "Rinnert")
    XCTAssertEqual(suggestions.first?.count, 2)
  }

  func testSingleOccurrenceIsBelowThreshold() {
    let observations = [changed("Frag mal Rinert dazu", "Frag mal Rinnert dazu")]
    XCTAssertTrue(ImprovementMiner.suggestions(from: observations).isEmpty)
  }

  func testAggregatesCaseInsensitivelyKeepingFirstCasing() {
    let observations = [
      changed(" wegen Notaben heute", "wegen Notabene heute"),
      changed("das Notaben Tool", "das Notabene Tool"),
    ]
    let suggestions = ImprovementMiner.suggestions(from: observations)
    XCTAssertEqual(suggestions.first?.from, "Notaben")
    XCTAssertEqual(suggestions.first?.to, "Notabene")
    XCTAssertEqual(suggestions.first?.count, 2)
  }

  // MARK: - Must NOT suggest

  func testMultiWordEditIsNotSuggested() {
    let observations = [
      changed("Das ist ganz toll", "Das war wirklich gut"),
      changed("Das ist ganz toll", "Das war wirklich gut"),
    ]
    XCTAssertTrue(ImprovementMiner.suggestions(from: observations).isEmpty)
  }

  func testDifferentTokenCountIsNotSuggested() {
    // An inserted word (length differs) is not a clean in-place substitution.
    let observations = [
      changed("Komm bitte her", "Komm doch bitte her"),
      changed("Komm bitte her", "Komm doch bitte her"),
    ]
    XCTAssertTrue(ImprovementMiner.suggestions(from: observations).isEmpty)
  }

  func testPunctuationOnlyDiffIsNotSuggested() {
    let observations = [
      changed("Bis dann Welt", "Bis dann Welt."),
      changed("Bis dann Welt", "Bis dann Welt."),
    ]
    XCTAssertTrue(ImprovementMiner.suggestions(from: observations).isEmpty)
  }

  func testShortWordIsNotSuggested() {
    // The changed core "ab" → "ob" is below the minimum word length (3) → too noisy to learn.
    let observations = [
      changed("Geh ab raus", "Geh ob raus"),
      changed("Geh ab raus", "Geh ob raus"),
    ]
    XCTAssertTrue(ImprovementMiner.suggestions(from: observations).isEmpty)
  }

  func testUnchangedObservationsAreIgnored() {
    let observations = [
      ImprovementMinerTests.make("Frag mal Rinert dazu", "Frag mal Rinert dazu", changed: false),
      ImprovementMinerTests.make("Frag mal Rinert dazu", "Frag mal Rinert dazu", changed: false),
    ]
    XCTAssertTrue(ImprovementMiner.suggestions(from: observations).isEmpty)
  }

  func testPairAlreadyInDictionaryIsExcluded() {
    let observations = [
      changed("Frag mal Rinert dazu", "Frag mal Rinnert dazu"),
      changed("Hallo Rinert wie gehts", "Hallo Rinnert wie gehts"),
    ]
    let suggestions = ImprovementMiner.suggestions(
      from: observations, existingFrom: ["rinert"])
    XCTAssertTrue(suggestions.isEmpty)
  }

  // MARK: - Ranking + cap

  func testSuggestionsAreRankedByCountAndCapped() {
    var observations: [ImprovementObservation] = []
    // 6 distinct recurring fixes (each ×2) — more than maxSuggestions (5).
    let pairs = [
      ("Aaaa", "Aaab"), ("Bbbb", "Bbbc"), ("Cccc", "Cccd"), ("Dddd", "Ddde"), ("Eeee", "Eeef"),
      ("Ffff", "Fffg"),
    ]
    for (index, pair) in pairs.enumerated() {
      // Give the first pair an extra occurrence so it ranks first.
      let times = index == 0 ? 3 : 2
      for _ in 0..<times {
        observations.append(changed("vor \(pair.0) nach", "vor \(pair.1) nach"))
      }
    }
    let suggestions = ImprovementMiner.suggestions(from: observations)
    XCTAssertEqual(suggestions.count, ImprovementMiner.maxSuggestions)
    XCTAssertEqual(suggestions.first?.from, "Aaaa")
    XCTAssertEqual(suggestions.first?.count, 3)
  }

  // MARK: - Conflict detection (R4-FT-suggest-direction-guard)

  func testInversePairIsAConflict() {
    // Dictionary already maps B→A; suggesting A→B would oscillate text → conflict.
    XCTAssertTrue(
      ImprovementMiner.conflictsWithExisting(
        from: "Rinnert", to: "Rinert", existing: [(from: "Rinert", to: "Rinnert")]))
  }

  func testInverseConflictIsCaseInsensitive() {
    XCTAssertTrue(
      ImprovementMiner.conflictsWithExisting(
        from: "FOO", to: "bar", existing: [(from: "Bar", to: "Foo")]))
  }

  func testNonInverseRulesAreNotAConflict() {
    XCTAssertFalse(
      ImprovementMiner.conflictsWithExisting(
        from: "Rinert", to: "Rinnert", existing: [(from: "Notaben", to: "Notabene")]))
    // Same-direction duplicate is handled separately (by `from` dedup), not flagged here.
    XCTAssertFalse(
      ImprovementMiner.conflictsWithExisting(
        from: "Rinert", to: "Rinnert", existing: [(from: "Rinert", to: "Rinnert")]))
    XCTAssertFalse(
      ImprovementMiner.conflictsWithExisting(from: "a", to: "b", existing: []))
  }

  // MARK: - singleWordChange direct

  func testSingleWordChangeReturnsCore() {
    let pair = ImprovementMiner.singleWordChange(
      inserted: "Frag mal „Rinert", final: "Frag mal „Rinnert")
    XCTAssertEqual(pair?.from, "Rinert")
    XCTAssertEqual(pair?.to, "Rinnert")
  }

  func testSingleWordChangeNilForVerbatim() {
    XCTAssertNil(ImprovementMiner.singleWordChange(inserted: "alles gleich", final: "alles gleich"))
  }

  // MARK: - Helpers

  private func changed(_ inserted: String, _ final: String) -> ImprovementObservation {
    ImprovementMinerTests.make(inserted, final, changed: true)
  }

  private static func make(
    _ inserted: String, _ final: String, changed: Bool
  ) -> ImprovementObservation {
    ImprovementObservation(
      date: Date(),
      appBundleID: "com.example.app",
      appName: "Example",
      mode: "transcription",
      inserted: inserted,
      finalText: final,
      changed: changed
    )
  }
}
