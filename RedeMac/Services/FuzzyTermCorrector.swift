import Foundation

/// Pure, on-device, deterministic fuzzy correction of the user's KNOWN terms (confirmed Memory
/// terms + Eigennamen). It snaps a CLEAR near-miss spelling Whisper produced — e.g. "Rinert" →
/// "Rinnert", "Blitztex" → "rede" — to the canonical term, preserving the term's casing.
///
/// CONSERVATIVE BY DESIGN. A false positive corrupts the user's text, so the bias is firmly toward
/// NOT correcting. The matcher only fires when a word (or 2-word span) is an unambiguous near-miss
/// of EXACTLY ONE canonical term. Guards:
///  - only canonical terms with length ≥ 4 are candidates,
///  - case-insensitive Levenshtein distance ≤ 1 (term length 4–6) or ≤ 2 (term length ≥ 7),
///  - the lengths are within ±2 of each other,
///  - an exact (case-insensitive) match is a no-op (never re-cased),
///  - a token that is a near-miss of TWO different terms is ambiguous → left untouched.
///
/// Runs AFTER `DictationPostProcessor` so literal dictionary replacements happen first. Empty
/// `terms` → no-op (zero overhead). Fully unit-testable: no I/O, no actor, no `AppState`.
enum FuzzyTermCorrector {

  /// Minimum canonical-term length to even be considered — short terms produce too many spurious
  /// near-misses against common words (e.g. "Tag" vs "Tat"), so they are excluded entirely.
  private static let minimumTermLength = 4

  /// Snaps near-miss words/2-word spans in `text` to a canonical `term`. Whitespace, punctuation
  /// and casing of the surrounding text are preserved; only the matched core word(s) are replaced.
  static func correct(_ text: String, terms: [String]) -> String {
    let canonical = canonicalTerms(from: terms)
    guard !canonical.isEmpty, !text.isEmpty else { return text }

    let tokens = tokenize(text)
    guard !tokens.isEmpty else { return text }

    var output = String()
    output.reserveCapacity(text.count)
    var index = 0
    while index < tokens.count {
      let advanced = appendCorrection(
        from: tokens, at: index, canonical: canonical, into: &output)
      index += advanced
    }
    return output
  }

  // MARK: - Canonical terms

  /// Trim, drop empties and anything shorter than `minimumTermLength`, de-dupe case-insensitively
  /// (first spelling wins, so the user's preferred casing is what gets applied).
  private static func canonicalTerms(from terms: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for term in terms {
      let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.count >= minimumTermLength else { continue }
      let key = trimmed.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(trimmed)
    }
    return result
  }

  // MARK: - Tokenization

  /// A run of text that is EITHER a whitespace gap OR a "word" (a non-whitespace chunk split into a
  /// leading-punctuation prefix, an alphanumeric core, and a trailing-punctuation suffix). Only the
  /// `core` is ever fuzzy-matched; `prefix`/`suffix`/whitespace are emitted verbatim.
  private struct Token {
    let isWhitespace: Bool
    let raw: String
    let prefix: String
    let core: String
    let suffix: String
  }

  private static func tokenize(_ text: String) -> [Token] {
    var tokens: [Token] = []
    var current = String()
    var currentIsWhitespace: Bool?

    func flush() {
      guard let isWhitespace = currentIsWhitespace, !current.isEmpty else { return }
      tokens.append(makeToken(current, isWhitespace: isWhitespace))
      current.removeAll(keepingCapacity: true)
    }

    for character in text {
      let isWhitespace = character.isWhitespace
      if currentIsWhitespace == nil || currentIsWhitespace == isWhitespace {
        current.append(character)
        currentIsWhitespace = isWhitespace
      } else {
        flush()
        current.append(character)
        currentIsWhitespace = isWhitespace
      }
    }
    flush()
    return tokens
  }

  /// Splits a non-whitespace chunk into leading punctuation, an alphanumeric core, and trailing
  /// punctuation (e.g. "„Rinert," → prefix "„", core "Rinert", suffix ","). Whitespace tokens and
  /// chunks without a clean core are stored with an empty core so they are never matched.
  private static func makeToken(_ raw: String, isWhitespace: Bool) -> Token {
    guard !isWhitespace else {
      return Token(isWhitespace: true, raw: raw, prefix: "", core: "", suffix: "")
    }
    let characters = Array(raw)
    var start = 0
    var end = characters.count
    while start < end, !characters[start].isLetterOrNumber { start += 1 }
    while end > start, !characters[end - 1].isLetterOrNumber { end -= 1 }
    let prefix = String(characters[0..<start])
    let core = String(characters[start..<end])
    let suffix = String(characters[end..<characters.count])
    return Token(isWhitespace: false, raw: raw, prefix: prefix, core: core, suffix: suffix)
  }

  // MARK: - Matching

  /// Tries a 2-word span first (names can be split, e.g. "Blitz Text"), then the single word.
  /// Emits the canonical term in place of the matched core(s) and returns how many tokens were
  /// consumed; on no match emits the token verbatim and consumes one.
  private static func appendCorrection(
    from tokens: [Token], at index: Int, canonical: [String], into output: inout String
  ) -> Int {
    let token = tokens[index]
    guard !token.isWhitespace, !token.core.isEmpty else {
      output.append(token.raw)
      return 1
    }

    if let (span, replacement) = twoWordMatch(tokens, at: index, canonical: canonical) {
      output.append(token.prefix)
      output.append(replacement)
      output.append(tokens[index + span - 1].suffix)
      return span
    }

    if let replacement = uniqueMatch(for: token.core, in: canonical) {
      output.append(token.prefix)
      output.append(replacement)
      output.append(token.suffix)
      return 1
    }

    output.append(token.raw)
    return 1
  }

  /// A 2-word span = this word's core + the next word's core joined with a space. Returns the span
  /// length (always 2) and the canonical replacement when that joined form uniquely matches a term.
  private static func twoWordMatch(
    _ tokens: [Token], at index: Int, canonical: [String]
  ) -> (span: Int, replacement: String)? {
    guard index + 2 < tokens.count else { return nil }
    let gap = tokens[index + 1]
    let next = tokens[index + 2]
    guard gap.isWhitespace, !next.isWhitespace, !next.core.isEmpty else { return nil }
    // Only join when nothing punctuation-like sits between the two cores, so we never merge across
    // a real boundary like "Rinert, und" → the gap must be plain and the first core suffix-free.
    guard tokens[index].suffix.isEmpty, next.prefix.isEmpty else { return nil }
    let joined = tokens[index].core + " " + next.core
    guard let replacement = uniqueMatch(for: joined, in: canonical) else { return nil }
    return (3, replacement)
  }

  /// Returns the canonical term iff `word` is a CLEAR near-miss of EXACTLY ONE term. An exact
  /// (case-insensitive) match is a no-op (returns nil → the word is emitted verbatim). Two or more
  /// equally-or-otherwise qualifying terms = ambiguous → nil (never guess).
  private static func uniqueMatch(for word: String, in canonical: [String]) -> String? {
    let lowerWord = word.lowercased()
    var match: String?
    for term in canonical {
      let lowerTerm = term.lowercased()
      // Exact match: nothing to correct. Return nil so casing is left exactly as dictated.
      if lowerWord == lowerTerm { return nil }
      guard isNearMiss(lowerWord, lowerTerm) else { continue }
      if match != nil { return nil }  // ambiguous: a second term also qualifies → bail out.
      match = term
    }
    return match
  }

  /// CLEAR near-miss test: lengths within ±2 AND case-insensitive Levenshtein distance within the
  /// term-length-scaled budget (≤ 1 for short terms, ≤ 2 for long ones). Both inputs are lowercased.
  private static func isNearMiss(_ word: String, _ term: String) -> Bool {
    let wordCount = word.count
    let termCount = term.count
    guard abs(wordCount - termCount) <= 2 else { return false }
    let budget = termCount >= 7 ? 2 : 1
    return levenshtein(Array(word), Array(term), budget: budget) <= budget
  }

  /// Bounded Levenshtein distance: returns the true distance when ≤ `budget`, otherwise any value
  /// > `budget` (early-outs once a whole row exceeds the budget). Keeps matching O(len²) per pair.
  private static func levenshtein(_ a: [Character], _ b: [Character], budget: Int) -> Int {
    var previous = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
      var current = [i] + Array(repeating: 0, count: b.count)
      var rowMin = i
      for j in 1...max(b.count, 1) where !b.isEmpty {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
        rowMin = min(rowMin, current[j])
      }
      if rowMin > budget { return budget + 1 }
      previous = current
    }
    return previous[b.count]
  }
}

extension Character {
  /// True for letters and decimal digits — the chars that form a matchable "core" word. Excludes
  /// punctuation/symbols so they stay in the prefix/suffix and are emitted verbatim.
  fileprivate var isLetterOrNumber: Bool { isLetter || isNumber }
}
