import XCTest

@testable import Rede

/// The Whisper hint has a hard 224-token budget, so the injected term set is capped (30) and
/// ordered so names+foreign rank first and the most important term lands LAST in the joined hint
/// (Whisper drops the EARLIEST tokens on overflow). These tests pin that contract.
///
/// `MemoryStore` is `@MainActor` and persists to disk; each test points it at a unique temp file
/// in a temp directory so nothing touches the real `memory.json`.
@MainActor
final class MemoryInjectionCapTests: XCTestCase {

  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("notabene-memtest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
  }

  private func makeStore() -> MemoryStore {
    MemoryStore(fileURL: tempDir.appendingPathComponent("memory-\(UUID().uuidString).json"))
  }

  // MARK: - Cap

  func testRankedInjectionTermsCapsAtInjectionCap() {
    let store = makeStore()
    // Confirm far more than the cap as generic terms.
    for index in 0..<200 {
      store.confirm(term: "Term\(index)", category: .term)
    }
    let injected = store.rankedInjectionTerms()
    XCTAssertEqual(MemoryStore.injectionCap, 30)
    XCTAssertEqual(injected.count, MemoryStore.injectionCap)
  }

  /// Auto-learned terms are bounded on disk: once over the cap, `decayAndPrune` keeps only the
  /// top `maxConfirmed` so the learned vocabulary stays a focused set instead of growing forever.
  func testConfirmedTermsPrunedToMaxConfirmed() {
    let store = makeStore()
    for index in 0..<(MemoryStore.maxConfirmed + 15) {
      store.confirm(term: "Term\(index)", category: .term)
    }
    XCTAssertGreaterThan(store.confirmed.count, MemoryStore.maxConfirmed)
    store.decayAndPrune()
    XCTAssertEqual(MemoryStore.maxConfirmed, 30)
    XCTAssertEqual(store.confirmed.count, MemoryStore.maxConfirmed)
  }

  func testRankedInjectionRespectsExplicitLowerLimit() {
    let store = makeStore()
    for index in 0..<100 { store.confirm(term: "Term\(index)", category: .term) }
    XCTAssertEqual(store.rankedInjectionTerms(limit: 10).count, 10)
  }

  // MARK: - Ordering: names/foreign prioritized, best LAST

  func testNamesAndForeignAreKeptOverGenericTermsUnderCap() {
    let store = makeStore()
    // 50 generic terms + 5 names + 5 foreign = 60 confirmed, injection cap 30.
    // Names (rank 0) + foreign (rank 1) outrank generic terms (rank 2), so all 10 survive.
    for index in 0..<50 { store.confirm(term: "Term\(index)", category: .term) }
    for index in 0..<5 { store.confirm(term: "Name\(index)", category: .name) }
    for index in 0..<5 { store.confirm(term: "Foreign\(index)", category: .foreign) }

    let injected = store.rankedInjectionTerms()
    XCTAssertEqual(injected.count, MemoryStore.injectionCap)

    let injectedSet = Set(injected)
    for index in 0..<5 {
      XCTAssertTrue(injectedSet.contains("Name\(index)"), "all names must survive the cap")
      XCTAssertTrue(injectedSet.contains("Foreign\(index)"), "all foreign must survive the cap")
    }
  }

  /// The list is REVERSED before injection, so the highest-priority terms (names) land LAST.
  /// With only names + foreign, the very last entry must be a name (rank 0 sorts first pre-reverse).
  func testHighestPriorityTermLandsLast() {
    let store = makeStore()
    store.confirm(term: "Foreign1", category: .foreign)
    store.confirm(term: "Foreign2", category: .foreign)
    store.confirm(term: "NameA", category: .name)
    store.confirm(term: "NameB", category: .name)

    let injected = store.rankedInjectionTerms()
    XCTAssertEqual(injected.count, 4)
    // Pre-reverse order is [names..., foreign...]; reversed -> foreign first, names last.
    XCTAssertTrue(
      injected.last == "NameA" || injected.last == "NameB",
      "a name (highest priority) must be the LAST token in the hint, got: \(String(describing: injected.last))"
    )
    XCTAssertTrue(
      injected.first == "Foreign1" || injected.first == "Foreign2",
      "lowest-priority term must be first, got: \(String(describing: injected.first))"
    )
  }

  // MARK: - LLM context block per-category cap

  func testContextSplitsByCategoryAndCapsPerCategory() {
    let store = makeStore()
    for index in 0..<20 { store.confirm(term: "Name\(index)", category: .name) }
    for index in 0..<20 { store.confirm(term: "Term\(index)", category: .term) }
    for index in 0..<20 { store.confirm(term: "Foreign\(index)", category: .foreign) }

    let context = store.context
    XCTAssertEqual(context.names.count, MemoryStore.llmBlockPerCategoryCap)
    XCTAssertEqual(context.terms.count, MemoryStore.llmBlockPerCategoryCap)
    XCTAssertEqual(context.foreign.count, MemoryStore.llmBlockPerCategoryCap)
    XCTAssertFalse(context.isEmpty)
  }

  func testEmptyStoreProducesEmptyContextAndNoInjection() {
    let store = makeStore()
    XCTAssertTrue(store.context.isEmpty)
    XCTAssertTrue(store.rankedInjectionTerms().isEmpty)
  }

  // MARK: - Dedup of confirm by id (lowercased term)

  func testConfirmingSameTermTwiceDoesNotDuplicate() {
    let store = makeStore()
    store.confirm(term: "Kubernetes", category: .term)
    store.confirm(term: "kubernetes", category: .term)  // same id (lowercased)
    XCTAssertEqual(store.confirmed.count, 1)
  }

  // MARK: - Auto vocabulary

  func testNamesAutoConfirmAfterTwoDocuments() {
    let store = makeStore()
    let term = ExtractedTerm(lemma: "Rinnert", surfaceForm: "Rinnert", category: .name)

    store.fold(extracted: [term], at: Date(timeIntervalSince1970: 1))
    XCTAssertTrue(store.confirmed.isEmpty)

    store.fold(extracted: [term], at: Date(timeIntervalSince1970: 2))
    XCTAssertEqual(store.confirmed.map(\.term), ["Rinnert"])
  }

  func testGenericTermsAutoConfirmAfterThreeDocuments() {
    let store = makeStore()
    let term = ExtractedTerm(lemma: "Kubernetes", surfaceForm: "Kubernetes", category: .term)

    store.fold(extracted: [term], at: Date(timeIntervalSince1970: 1))
    store.fold(extracted: [term], at: Date(timeIntervalSince1970: 2))
    XCTAssertTrue(store.confirmed.isEmpty)

    store.fold(extracted: [term], at: Date(timeIntervalSince1970: 3))
    XCTAssertEqual(store.confirmed.map(\.term), ["Kubernetes"])
  }

  func testCommonTermsDoNotAutoConfirm() {
    let store = makeStore()
    let term = ExtractedTerm(lemma: "Termin", surfaceForm: "Termin", category: .term)

    for offset in 0..<5 {
      store.fold(extracted: [term], at: Date(timeIntervalSince1970: Double(offset)))
    }

    XCTAssertTrue(store.confirmed.isEmpty)
  }

  func testHighFrequencyGermanWordsDoNotAutoConfirm() {
    let store = makeStore()
    let terms = ["der", "und", "für", "nicht", "haben", "werden"].map {
      ExtractedTerm(lemma: $0, surfaceForm: $0, category: .term)
    }

    for offset in 0..<5 {
      store.fold(extracted: terms, at: Date(timeIntervalSince1970: Double(offset)))
    }

    XCTAssertTrue(store.confirmed.isEmpty)
  }

  func testHighFrequencyEnglishWordsDoNotAutoConfirm() {
    let store = makeStore()
    let terms = ["the", "and", "because", "have", "would", "people"].map {
      ExtractedTerm(lemma: $0, surfaceForm: $0, category: .term)
    }

    for offset in 0..<5 {
      store.fold(extracted: terms, at: Date(timeIntervalSince1970: Double(offset)))
    }

    XCTAssertTrue(store.confirmed.isEmpty)
  }

  func testCommonWordListsHaveTwoHundredWordsPerLanguage() {
    XCTAssertGreaterThanOrEqual(MemoryCommonWords.germanTopWords.count, 200)
    XCTAssertGreaterThanOrEqual(MemoryCommonWords.englishTopWords.count, 200)
    XCTAssertTrue(MemoryCommonWords.contains("für"))
    XCTAssertTrue(MemoryCommonWords.contains("fuer"))
    XCTAssertTrue(MemoryCommonWords.contains("The"))
  }

  func testDeniedTermDoesNotAutoConfirmAgain() {
    let store = makeStore()
    let term = ExtractedTerm(lemma: "Kubernetes", surfaceForm: "Kubernetes", category: .term)

    store.deny(term: "Kubernetes")
    for offset in 0..<5 {
      store.fold(extracted: [term], at: Date(timeIntervalSince1970: Double(offset)))
    }

    XCTAssertTrue(store.confirmed.isEmpty)
    XCTAssertTrue(store.candidates.isEmpty)
  }

  // MARK: - LLMService memory block rendering (pure)

  func testMemoryContextBlockRendersCategoriesAndIsNilWhenEmpty() {
    XCTAssertNil(LLMService.memoryContextBlock(MemoryContext(names: [], terms: [], foreign: [])))

    let block = try? XCTUnwrap(
      LLMService.memoryContextBlock(
        MemoryContext(names: ["Rinnert"], terms: ["Lektor"], foreign: ["Deadline"])
      ))
    let text = try? XCTUnwrap(block)
    XCTAssertTrue(text?.contains("Namen: Rinnert") ?? false)
    XCTAssertTrue(text?.contains("Fachbegriffe: Lektor") ?? false)
    XCTAssertTrue(text?.contains("Fremdwörter: Deadline") ?? false)
  }
}
