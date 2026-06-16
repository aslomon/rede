import XCTest

@testable import Rede

/// R2-FT-stats core: pins the pure `DictationStats.compute` aggregate over the text-only archive.
/// Word counting, per-mode aggregation/sort, the time-saved math, the recording-seconds sum and the
/// empty-archive case are all deterministic and provider-free — no AppKit / AX / disk state.
final class DictationStatsTests: XCTestCase {

  // MARK: - Helpers

  private func entry(
    mode: WorkflowType,
    finalText: String,
    durationSec: Double = 0,
    date: Date = Date()
  ) -> ArchiveEntry {
    ArchiveEntry(
      date: date,
      mode: mode,
      rawTranscript: finalText,
      finalText: finalText,
      backend: .remote,
      durationSec: durationSec
    )
  }

  // MARK: - Word counting

  func testWordCountSplitsOnSpacesNewlinesAndTabs() {
    XCTAssertEqual(DictationStats.wordCount(of: "Hallo  Welt"), 2)
    XCTAssertEqual(DictationStats.wordCount(of: "eins\nzwei\tdrei"), 3)
    XCTAssertEqual(DictationStats.wordCount(of: "   führende und   mehrfache   Leerzeichen  "), 4)
  }

  func testWordCountEmptyAndWhitespaceOnlyIsZero() {
    XCTAssertEqual(DictationStats.wordCount(of: ""), 0)
    XCTAssertEqual(DictationStats.wordCount(of: "   \n\t  "), 0)
  }

  // MARK: - Total runs

  func testTotalRunsEqualsEntryCount() {
    let entries = [
      entry(mode: .transcription, finalText: "ein wort hier"),
      entry(mode: .textImprover, finalText: "noch eins"),
      entry(mode: .transcription, finalText: "drittes"),
    ]
    XCTAssertEqual(DictationStats.compute(from: entries).totalRuns, 3)
  }

  // MARK: - Total words

  func testTotalWordsSumsAcrossEntries() {
    let entries = [
      entry(mode: .transcription, finalText: "ein zwei drei"),  // 3
      entry(mode: .textImprover, finalText: "vier  fünf"),  // 2
    ]
    XCTAssertEqual(DictationStats.compute(from: entries).totalWords, 5)
  }

  // MARK: - Per-mode aggregation + sort

  func testPerModeAggregatesAndSortsByRunsDescending() {
    let entries = [
      entry(mode: .textImprover, finalText: "a b"),  // textImprover: 1 run, 2 words
      entry(mode: .transcription, finalText: "a"),  // transcription run 1
      entry(mode: .transcription, finalText: "b c"),  // transcription run 2
      entry(mode: .transcription, finalText: "d"),  // transcription run 3
    ]

    let perMode = DictationStats.compute(from: entries).perMode
    XCTAssertEqual(perMode.count, 2)
    // Sorted by runs desc: transcription (3) before textImprover (1).
    XCTAssertEqual(perMode[0].mode, .transcription)
    XCTAssertEqual(perMode[0].runs, 3)
    XCTAssertEqual(perMode[0].words, 4)
    XCTAssertEqual(perMode[1].mode, .textImprover)
    XCTAssertEqual(perMode[1].runs, 1)
    XCTAssertEqual(perMode[1].words, 2)
  }

  func testPerModeTieOnRunsBreaksByWordsDescending() {
    let entries = [
      entry(mode: .transcription, finalText: "ein wort"),  // 1 run, 2 words
      entry(mode: .textImprover, finalText: "ein zwei drei vier"),  // 1 run, 4 words
    ]
    let perMode = DictationStats.compute(from: entries).perMode
    // Equal runs (1 each) → the higher word count wins the tie.
    XCTAssertEqual(perMode[0].mode, .textImprover)
    XCTAssertEqual(perMode[1].mode, .transcription)
  }

  // MARK: - Time-saved math

  func testTimeSavedIs60SecondsFor38WordsAt38Wpm() {
    // 38 words / 38 wpm * 60 = exactly 60 seconds.
    let words38 = Array(repeating: "wort", count: 38).joined(separator: " ")
    let stats = DictationStats.compute(
      from: [entry(mode: .transcription, finalText: words38)],
      typingWordsPerMinute: 38
    )
    XCTAssertEqual(stats.totalWords, 38)
    XCTAssertEqual(stats.estimatedTypingSecondsSaved, 60, accuracy: 0.0001)
  }

  func testTimeSavedNonPositiveRateYieldsZero() {
    let stats = DictationStats.compute(
      from: [entry(mode: .transcription, finalText: "ein zwei drei")],
      typingWordsPerMinute: 0
    )
    XCTAssertEqual(stats.estimatedTypingSecondsSaved, 0)
  }

  // MARK: - Recording-seconds sum

  func testRecordingSecondsSumIgnoresNegativeDurations() {
    let entries = [
      entry(mode: .transcription, finalText: "a", durationSec: 12.5),
      entry(mode: .transcription, finalText: "b", durationSec: 7.5),
      entry(mode: .transcription, finalText: "c", durationSec: -100),  // clamped to 0
    ]
    XCTAssertEqual(
      DictationStats.compute(from: entries).totalRecordingSeconds, 20, accuracy: 0.0001)
  }

  // MARK: - Empty

  func testEmptyEntriesProduceZeroedStats() {
    let stats = DictationStats.compute(from: [])
    XCTAssertTrue(stats.isEmpty)
    XCTAssertEqual(stats.totalRuns, 0)
    XCTAssertEqual(stats.totalWords, 0)
    XCTAssertEqual(stats.totalRecordingSeconds, 0)
    XCTAssertEqual(stats.estimatedTypingSecondsSaved, 0)
    XCTAssertTrue(stats.perMode.isEmpty)
    XCTAssertEqual(stats, DictationStats.empty)
  }

  // MARK: - since: filter ("letzte 7 Tage")

  func testSinceFilterExcludesOlderEntries() {
    let now = Date()
    let recent = now.addingTimeInterval(-60 * 60)  // 1 hour ago
    let old = now.addingTimeInterval(-60 * 60 * 24 * 30)  // 30 days ago
    let entries = [
      entry(mode: .transcription, finalText: "neu eins zwei", date: recent),  // 3 words
      entry(mode: .transcription, finalText: "alt drei vier fünf", date: old),  // excluded
    ]

    let cutoff = now.addingTimeInterval(-60 * 60 * 24 * 7)  // 7 days ago
    let stats = DictationStats.compute(from: entries, since: cutoff)
    XCTAssertEqual(stats.totalRuns, 1)
    XCTAssertEqual(stats.totalWords, 3)
  }
}
