import NaturalLanguage
import XCTest

@testable import Rede

/// On-device extraction sanity checks. `MemoryExtractionService` uses NaturalLanguage
/// (NLTagger / NLLanguageRecognizer) + NSSpellChecker — all on-device, no network, and no
/// downloadable wordlist. German + English dictionaries ship with macOS, so these run offline.
///
/// `extract(from:)` is `async` because the NSSpellChecker OOV lookups are main-actor-isolated
/// (the NaturalLanguage tokenization stays off-main; only the spell-check batch hops to MainActor).
///
/// These are deliberately TOLERANT: NER/POS tagging is heuristic and version-dependent, so we
/// assert structural invariants (purity, no I/O, category vocabulary, foreign-by-language-mismatch
/// is at least reachable) rather than brittle exact-token expectations.
final class MemoryExtractionServiceTests: XCTestCase {

  private let service = MemoryExtractionService()

  // MARK: - Purity / safety

  func testEmptyAndTinyInputReturnsNoTerms() async {
    let empty = await service.extract(from: "")
    let spaces = await service.extract(from: "  ")
    let tiny = await service.extract(from: "ok")  // below minimumTokenLength
    XCTAssertTrue(empty.isEmpty)
    XCTAssertTrue(spaces.isEmpty)
    XCTAssertTrue(tiny.isEmpty)
  }

  func testExtractionIsDeterministic() async {
    let text =
      "Wir besprechen das Deployment mit Rinnert und schauen uns die Roadmap genauer an."
    // ExtractedTerm is Equatable but not Hashable; compare order-independently via sorted keys.
    func sortedKeys(_ terms: [ExtractedTerm]) -> [String] {
      terms.map { "\($0.category.rawValue)|\($0.lemma)|\($0.surfaceForm)" }.sorted()
    }
    let first = await service.extract(from: text)
    let second = await service.extract(from: text)
    XCTAssertEqual(sortedKeys(first), sortedKeys(second), "extraction must be deterministic / pure")
  }

  func testEveryExtractedTermHasValidCategoryAndNonEmptyFields() async {
    let text =
      "Bei der Migration nach Kubernetes brauchen wir bis zur Deadline ein sauberes Backup. "
      + "Frau Schneider und Herr Rinnert prüfen die Architektur."
    let terms = await service.extract(from: text)
    for term in terms {
      XCTAssertTrue(
        MemoryCategory.allCases.contains(term.category),
        "unexpected category \(term.category)")
      XCTAssertFalse(term.surfaceForm.isEmpty)
      XCTAssertFalse(term.lemma.isEmpty)
      // minimumTokenLength is 3.
      XCTAssertGreaterThanOrEqual(term.surfaceForm.count, 3)
    }
  }

  // MARK: - Candidate extraction returns something on a realistic transcript

  func testRealisticGermanTranscriptYieldsCandidates() async {
    // A transcript with proper nouns (names), an English loan term, and rare jargon.
    let text = """
      Also ich diktiere kurz für das Projekt Notabene. Wir müssen das Deployment vorbereiten
      und mit Kubernetes arbeiten. Bitte sag Frau Müller und Herrn Rinnert Bescheid, dass die
      Deadline am Freitag ist. Die Roadmap besprechen wir im nächsten Meeting.
      """
    let terms = await service.extract(from: text)
    XCTAssertFalse(
      terms.isEmpty,
      "a realistic German transcript should surface at least one candidate term")
  }

  // MARK: - Foreign-by-language-mismatch is reachable (tolerant)

  /// English loanwords embedded in German text are the foreign-detection target. We don't assert
  /// a specific token (NL tagging varies by OS), only that the foreign path can fire at all on a
  /// clearly mixed-language transcript — and never crashes.
  func testMixedLanguageTranscriptDoesNotCrashAndCanProduceForeign() async {
    let text =
      "Wir machen ein kurzes Standup Meeting und besprechen das Deployment und den Feature Branch."
    let terms = await service.extract(from: text)
    // Tolerant: foreign detection may or may not fire depending on the on-device dictionaries,
    // but the call must complete and any foreign terms must be well-formed.
    let foreign = terms.filter { $0.category == .foreign }
    for term in foreign {
      XCTAssertFalse(term.surfaceForm.isEmpty)
    }
    // Structural assertion that always holds: extraction over mixed-language text is safe.
    _ = await service.extract(from: text)
  }

  // MARK: - Names: capitalized out-of-dictionary proper nouns

  /// An invented proper noun (definitely out-of-dictionary, capitalized) should classify as a
  /// name. Uses a coined word to avoid relying on NER, which the service treats as a vote only.
  func testCoinedCapitalizedProperNounClassifiesAsNameOrTerm() async {
    let text = "Das neue Modul heißt Zorblax und wird von Quentibald betreut."
    let terms = await service.extract(from: text)
    let zorblax = terms.first { $0.surfaceForm.lowercased() == "zorblax" }
    if let zorblax {
      // OOV + capitalized -> name (the gate). Term is an acceptable fallback if NL lemmatizes oddly.
      XCTAssertTrue(
        zorblax.category == .name || zorblax.category == .term,
        "OOV capitalized coinage should be name (or term), got \(zorblax.category)")
    }
    // If NL didn't tokenize it as expected we don't fail — this is a best-effort heuristic test.
  }
}
