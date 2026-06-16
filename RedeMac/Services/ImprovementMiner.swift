import Foundation

/// MEM-2b: turns the passive improvement log into ACTIONABLE, on-device suggestions. It mines the
/// recorded before→after corrections (`ImprovementObservation`) for a recurring, deterministic
/// single-word fix — e.g. the user repeatedly changes "Rinert" → "Rinnert" — and proposes it as a
/// confirmable `DictationDictionary` replacement. Closing the loop the log itself flagged as open.
///
/// CONSERVATIVE BY DESIGN (a bad suggestion teaches the app to corrupt text):
///  - only `changed` observations whose before/after differ in EXACTLY ONE whitespace token,
///  - the differing word's alphanumeric core must be ≥ `minimumWordLength` and actually changed,
///  - a pair must recur in ≥ `minimumOccurrences` distinct observations,
///  - pairs already covered by an existing dictionary replacement are excluded.
///
/// Pure + side-effect-free (no AppState / AX / I/O) so it is fully unit-testable.
enum ImprovementMiner {

  /// A learnable replacement the user can accept into the dictation dictionary. `count` is how many
  /// distinct corrections produced it — used to rank and to justify the suggestion in the UI.
  struct Suggestion: Sendable, Hashable, Identifiable {
    let from: String
    let to: String
    let count: Int
    /// Stable identity for SwiftUI lists, derived from the (case-insensitive) pair.
    var id: String { Self.key(from: from, to: to) }

    static func key(from: String, to: String) -> String {
      from.lowercased() + "→" + to.lowercased()
    }
  }

  /// A pair must recur at least this often before it's trusted as a real, repeatable correction
  /// rather than a one-off edit.
  static let minimumOccurrences = 2

  /// The changed word's core must be at least this long — short tokens ("er"/"es") produce noisy,
  /// risky substring replacements.
  static let minimumWordLength = 3

  /// Cap on how many suggestions to surface, highest-count first, so the UI never floods.
  static let maxSuggestions = 5

  /// Mines `observations` for recurring single-word corrections not already in `existingFrom`
  /// (the set of `from` strings already in the dictionary, compared case-insensitively).
  static func suggestions(
    from observations: [ImprovementObservation], existingFrom: Set<String> = []
  ) -> [Suggestion] {
    let existing = Set(existingFrom.map { $0.lowercased() })

    // Aggregate (fromLower→toLower) → (count, first-seen casing). First casing wins so we keep the
    // user's actual spelling rather than a lowercased form.
    var counts: [String: Int] = [:]
    var display: [String: (from: String, to: String)] = [:]

    for observation in observations where observation.changed {
      guard
        let pair = singleWordChange(inserted: observation.inserted, final: observation.finalText)
      else { continue }
      let key = Suggestion.key(from: pair.from, to: pair.to)
      counts[key, default: 0] += 1
      if display[key] == nil { display[key] = pair }
    }

    return
      counts
      .filter { $0.value >= minimumOccurrences }
      .compactMap { key, count -> Suggestion? in
        guard let pair = display[key] else { return nil }
        guard !existing.contains(pair.from.lowercased()) else { return nil }
        return Suggestion(from: pair.from, to: pair.to, count: count)
      }
      .sorted { lhs, rhs in
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.from.lowercased() < rhs.from.lowercased()
      }
      .prefix(maxSuggestions)
      .map { $0 }
  }

  // MARK: - Conflict detection

  /// True when accepting `from→to` would FIGHT an existing dictionary rule — i.e. the dictionary
  /// already maps `to→from` (the exact inverse). Adding both creates an oscillating pair that
  /// corrupts text non-deterministically by replacement order, so the accept path must refuse it.
  /// Pure + case-insensitive so it is unit-testable.
  static func conflictsWithExisting(
    from: String, to: String, existing: [(from: String, to: String)]
  ) -> Bool {
    let f = from.lowercased()
    let t = to.lowercased()
    return existing.contains { $0.from.lowercased() == t && $0.to.lowercased() == f }
  }

  // MARK: - Single-word change detection

  /// Returns the (from → to) word pair when `inserted` and `final` differ in EXACTLY ONE
  /// whitespace token, whose punctuation-stripped cores are a real, non-trivial change. `nil`
  /// otherwise (multi-word edits, insertions/deletions, punctuation-only diffs, too-short words).
  static func singleWordChange(inserted: String, final: String) -> (from: String, to: String)? {
    let insertedTokens = inserted.split(separator: " ", omittingEmptySubsequences: true).map(
      String.init)
    let finalTokens = final.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard insertedTokens.count == finalTokens.count, !insertedTokens.isEmpty else { return nil }

    var differingIndex: Int?
    for index in insertedTokens.indices where insertedTokens[index] != finalTokens[index] {
      if differingIndex != nil { return nil }  // more than one token differs → not a clean fix
      differingIndex = index
    }
    guard let index = differingIndex else { return nil }

    let fromCore = core(of: insertedTokens[index])
    let toCore = core(of: finalTokens[index])
    guard fromCore.count >= minimumWordLength, !toCore.isEmpty else { return nil }
    guard fromCore.lowercased() != toCore.lowercased() else { return nil }
    guard fromCore.contains(where: { $0.isLetter }) else { return nil }
    return (from: fromCore, to: toCore)
  }

  /// Strips leading/trailing non-alphanumerics so "„Rinert," compares as "Rinert".
  private static func core(of token: String) -> String {
    let characters = Array(token)
    var start = 0
    var end = characters.count
    while start < end, !(characters[start].isLetter || characters[start].isNumber) { start += 1 }
    while end > start, !(characters[end - 1].isLetter || characters[end - 1].isNumber) { end -= 1 }
    return String(characters[start..<end])
  }
}
