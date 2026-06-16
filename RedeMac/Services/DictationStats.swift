import Foundation

// MARK: - Dictation statistics (R2-FT-stats)

/// Pure, deterministic aggregate over the EXISTING text-only archive — no new capture, no privacy
/// cost. Read-only: it derives engaging totals (runs, dictated words, recording time and an
/// estimate of the typing time saved) plus a per-mode breakdown. All values are computed in one
/// pass so the view can render live from `ArchiveStore.entries`.
struct DictationStats: Equatable, Sendable {
  let totalRuns: Int
  let totalWords: Int
  let totalRecordingSeconds: Double
  /// Estimated seconds the user did NOT spend typing, at `typingWordsPerMinute`. Clamped ≥ 0.
  let estimatedTypingSecondsSaved: Double
  /// Per-mode aggregate, sorted by `runs` descending (ties broken by `words` descending).
  let perMode: [ModeStat]

  struct ModeStat: Equatable, Sendable {
    let mode: WorkflowType
    let runs: Int
    let words: Int
  }

  /// Average typing speed used to estimate the time saved. 38 wpm is a conservative
  /// real-world prose-typing rate (faster than the ~40 wpm raw average once edits are included).
  static let defaultTypingWordsPerMinute: Double = 38

  /// True when the archive held no entries — the view shows its empty state for this.
  var isEmpty: Bool { totalRuns == 0 }

  /// Zeroed stats, used for an empty archive.
  static let empty = DictationStats(
    totalRuns: 0,
    totalWords: 0,
    totalRecordingSeconds: 0,
    estimatedTypingSecondsSaved: 0,
    perMode: []
  )

  // MARK: - Compute

  /// Aggregates the given entries in a single pass. Pure and deterministic.
  /// - Parameters:
  ///   - entries: archive entries (any order); only `finalText`, `mode` and `durationSec` are read.
  ///   - typingWordsPerMinute: typing speed for the time-saved estimate (must be > 0 to count).
  static func compute(
    from entries: [ArchiveEntry],
    typingWordsPerMinute: Double = defaultTypingWordsPerMinute
  ) -> DictationStats {
    guard !entries.isEmpty else { return .empty }

    var totalWords = 0
    var totalRecordingSeconds = 0.0
    var runsByMode: [WorkflowType: Int] = [:]
    var wordsByMode: [WorkflowType: Int] = [:]

    for entry in entries {
      let words = wordCount(of: entry.finalText)
      totalWords += words
      totalRecordingSeconds += max(entry.durationSec, 0)
      runsByMode[entry.mode, default: 0] += 1
      wordsByMode[entry.mode, default: 0] += words
    }

    return DictationStats(
      totalRuns: entries.count,
      totalWords: totalWords,
      totalRecordingSeconds: totalRecordingSeconds,
      estimatedTypingSecondsSaved: typingSecondsSaved(
        words: totalWords, wordsPerMinute: typingWordsPerMinute),
      perMode: sortedModeStats(runsByMode: runsByMode, wordsByMode: wordsByMode)
    )
  }

  /// Convenience: aggregate only the entries on or after `date`. Pure filter + `compute`.
  static func compute(
    from entries: [ArchiveEntry],
    since date: Date,
    typingWordsPerMinute: Double = defaultTypingWordsPerMinute
  ) -> DictationStats {
    compute(from: entries.filter { $0.date >= date }, typingWordsPerMinute: typingWordsPerMinute)
  }

  // MARK: - Pure helpers

  /// Whitespace-split count of non-empty tokens (spaces, tabs and newlines all separate words).
  static func wordCount(of text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
      .filter { !$0.isEmpty }
      .count
  }

  /// Estimated typing time (seconds) for `words` at `wordsPerMinute`. Clamped ≥ 0; a non-positive
  /// rate yields 0 (avoids division by zero / nonsense estimates).
  private static func typingSecondsSaved(words: Int, wordsPerMinute: Double) -> Double {
    guard words > 0, wordsPerMinute > 0 else { return 0 }
    return max(Double(words) / wordsPerMinute * 60, 0)
  }

  /// Builds the per-mode list sorted by runs desc, then words desc, then mode order for stability.
  private static func sortedModeStats(
    runsByMode: [WorkflowType: Int],
    wordsByMode: [WorkflowType: Int]
  ) -> [ModeStat] {
    runsByMode
      .map { ModeStat(mode: $0.key, runs: $0.value, words: wordsByMode[$0.key] ?? 0) }
      .sorted { lhs, rhs in
        if lhs.runs != rhs.runs { return lhs.runs > rhs.runs }
        if lhs.words != rhs.words { return lhs.words > rhs.words }
        return lhs.mode.rawValue < rhs.mode.rawValue
      }
  }
}
