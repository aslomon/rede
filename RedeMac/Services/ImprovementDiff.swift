import Foundation

/// Pure, side-effect-free matcher for the "Verbesserungs-Erkennung" (MEM-2). Given the text
/// rede inserted and the field's CURRENT value (re-read later via AX), it decides whether the
/// user edited our text in place — and if so, recovers the edited version.
///
/// Conservative by design: it only reports an edit when an edited region is CLEARLY the same
/// neighborhood as what we inserted (anchored on a stable prefix + suffix, gated by a token/char
/// similarity check). When the inserted text can't be located at all (the user navigated away or
/// replaced everything), it returns `nil` rather than guessing. Fully testable without any AX state.
enum ImprovementDiff {
  /// Minimum similarity (0...1) between the inserted text and a candidate edited region for it to
  /// count as "the same text, edited" rather than unrelated field content. Tuned to accept typical
  /// copy-edits (a few words changed) while rejecting wholly different surrounding content.
  static let minimumSimilarity = 0.55

  /// Anchors shorter than this (in characters) are too weak to trust as a unique locator, so an
  /// anchored edited-region extraction is rejected to avoid matching on incidental short fragments.
  static let minimumAnchorLength = 4

  /// Above this input length the per-character `contains` anchor scan in `stablePrefix/Suffix` gets
  /// quadratic, so on large inputs we run only the cheap verbatim check and skip recovery. Mirrors
  /// the `PasteContextAXReader.maxValueLength` field cap; here it also guards direct/test callers.
  static let maxDiffInputLength = 20_000

  /// Result: whether our text was changed, and the text that now stands where we inserted it.
  /// `nil` (from `observe`) means "can't locate our insertion" — never recorded.
  ///
  /// - Parameters:
  ///   - inserted: the exact text rede pasted.
  ///   - fieldValue: the field's current full value, re-read later via AX.
  static func observe(inserted: String, fieldValue: String) -> (changed: Bool, finalText: String)? {
    let insertedTrimmed = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !insertedTrimmed.isEmpty else { return nil }

    // 1. Verbatim (or trimmed / whitespace-normalized) substring → unchanged.
    if containsVerbatim(inserted: insertedTrimmed, fieldValue: fieldValue) {
      return (changed: false, finalText: insertedTrimmed)
    }

    // Bound the expensive anchored recovery: above the cap the per-character anchor scan is O(n²),
    // so we stop here (the cheap verbatim check above already ran) rather than stall the main actor.
    guard insertedTrimmed.count <= maxDiffInputLength, fieldValue.count <= maxDiffInputLength else {
      return nil
    }

    // 2. Try to recover an edited-in-place region anchored on a stable prefix + suffix.
    if let edited = editedRegion(inserted: insertedTrimmed, fieldValue: fieldValue) {
      return (changed: true, finalText: edited)
    }

    // 3. Can't locate our insertion at all — don't guess.
    return nil
  }

  // MARK: - Verbatim detection

  /// True when the inserted text still appears in the field unchanged, allowing for surrounding
  /// edits and whitespace differences (exact substring, then whitespace-normalized substring).
  private static func containsVerbatim(inserted: String, fieldValue: String) -> Bool {
    if fieldValue.contains(inserted) { return true }
    let normalizedField = normalizeWhitespace(fieldValue)
    let normalizedInserted = normalizeWhitespace(inserted)
    guard !normalizedInserted.isEmpty else { return false }
    return normalizedField.contains(normalizedInserted)
  }

  // MARK: - Edited-region recovery

  /// Recovers the text that now stands where we inserted, when the user edited it in place.
  /// Strategy: find the longest stable prefix and suffix of the inserted text that still appear in
  /// the field (in order); the span between them is the edited region. Guarded by a similarity check
  /// so unrelated content between two incidentally-matching anchors isn't mistaken for an edit.
  private static func editedRegion(inserted: String, fieldValue: String) -> String? {
    guard !fieldValue.isEmpty else { return nil }

    let prefix = stablePrefix(of: inserted, in: fieldValue)
    let suffix = stableSuffix(of: inserted, in: fieldValue)

    // Need at least one trustworthy anchor; otherwise we'd be guessing.
    guard prefix.count >= minimumAnchorLength || suffix.count >= minimumAnchorLength else {
      return nil
    }

    guard let region = span(in: fieldValue, between: prefix, and: suffix) else { return nil }
    let edited = region.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !edited.isEmpty, edited != inserted else { return nil }

    // Similarity guard: the recovered region must clearly be a corrected version of our text,
    // not a stretch of unrelated field content that merely sits between two matching anchors.
    guard similarity(inserted, edited) >= minimumSimilarity else { return nil }
    return edited
  }

  /// The longest leading run of the inserted text that still occurs verbatim in the field.
  private static func stablePrefix(of inserted: String, in fieldValue: String) -> String {
    var anchor = ""
    var candidate = ""
    for character in inserted {
      candidate.append(character)
      if fieldValue.contains(candidate) {
        anchor = candidate
      } else {
        break
      }
    }
    return anchor
  }

  /// The longest trailing run of the inserted text that still occurs verbatim in the field.
  private static func stableSuffix(of inserted: String, in fieldValue: String) -> String {
    var anchor = ""
    var candidate = ""
    for character in inserted.reversed() {
      candidate = String(character) + candidate
      if fieldValue.contains(candidate) {
        anchor = candidate
      } else {
        break
      }
    }
    return anchor
  }

  /// The substring of `fieldValue` that lies between the prefix anchor and the suffix anchor
  /// (suffix located AFTER the prefix). Returns the full anchored span including the anchors,
  /// so a corrected region with intact ends is recovered as the user now sees it.
  private static func span(in fieldValue: String, between prefix: String, and suffix: String)
    -> String?
  {
    let startIndex: String.Index
    if prefix.isEmpty {
      startIndex = fieldValue.startIndex
    } else if let prefixRange = fieldValue.range(of: prefix) {
      startIndex = prefixRange.lowerBound
    } else {
      return nil
    }

    let endIndex: String.Index
    if suffix.isEmpty {
      endIndex = fieldValue.endIndex
    } else if let suffixRange = fieldValue.range(
      of: suffix, range: startIndex..<fieldValue.endIndex)
    {
      endIndex = suffixRange.upperBound
    } else {
      return nil
    }

    guard startIndex <= endIndex else { return nil }
    return String(fieldValue[startIndex..<endIndex])
  }

  // MARK: - Similarity

  /// A token-overlap (Jaccard) similarity in 0...1, with a character-level fallback for short or
  /// single-token strings. Pure and locale-light: lowercased, whitespace-tokenized.
  static func similarity(_ lhs: String, _ rhs: String) -> Double {
    let lhsTokens = tokenSet(lhs)
    let rhsTokens = tokenSet(rhs)
    if lhsTokens.count >= 2 && rhsTokens.count >= 2 {
      let intersection = lhsTokens.intersection(rhsTokens).count
      let union = lhsTokens.union(rhsTokens).count
      guard union > 0 else { return 0 }
      return Double(intersection) / Double(union)
    }
    return characterSimilarity(lhs, rhs)
  }

  private static func tokenSet(_ text: String) -> Set<String> {
    Set(
      text.lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
    )
  }

  /// Character-bigram overlap fallback for short strings where token overlap is too coarse.
  private static func characterSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let lhsGrams = bigrams(lhs.lowercased())
    let rhsGrams = bigrams(rhs.lowercased())
    if lhsGrams.isEmpty && rhsGrams.isEmpty { return lhs.lowercased() == rhs.lowercased() ? 1 : 0 }
    let intersection = lhsGrams.intersection(rhsGrams).count
    let union = lhsGrams.union(rhsGrams).count
    guard union > 0 else { return 0 }
    return Double(intersection) / Double(union)
  }

  private static func bigrams(_ text: String) -> Set<String> {
    let characters = Array(text)
    guard characters.count >= 2 else { return Set(characters.map(String.init)) }
    var grams = Set<String>()
    for index in 0..<(characters.count - 1) {
      grams.insert(String(characters[index...index + 1]))
    }
    return grams
  }

  // MARK: - Whitespace normalization

  /// Collapses every run of whitespace/newlines to a single space and trims the ends, so a field
  /// that re-wrapped or re-spaced our text still reads as "unchanged".
  private static func normalizeWhitespace(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
