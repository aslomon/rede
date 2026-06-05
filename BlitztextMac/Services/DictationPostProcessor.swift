import Foundation

/// Pure, on-device, deterministic post-processing of a cleaned transcript BEFORE rewrite/paste.
///
/// Order:
///  1. Literal replacements (case-insensitive match; whole-word vs substring; user's `to` casing).
///  2. Spoken-punctuation mapping (when enabled): standalone spoken tokens → punctuation, attached
///     to the preceding word with no leading space, double spaces collapsed.
///
/// Fully unit-testable: no I/O, no actor, no `AppState` dependency.
enum DictationPostProcessor {

  /// Single source of truth for the spoken-punctuation mapping, in display order.
  /// `spoken` is the human-facing label (as the user would say it); `symbol` is the rendered
  /// punctuation for the UI reference (`⏎` for line breaks). The matcher lowercases `spoken`
  /// and matches it as a WHOLE word only. The UI in `DictationDictionarySection` reads this
  /// array so the reference list and the actual behavior can never drift apart.
  static let punctuationReference: [(spoken: String, symbol: String)] = [
    ("Komma", ","),
    ("Punkt", "."),
    ("Fragezeichen", "?"),
    ("Ausrufezeichen", "!"),
    ("Doppelpunkt", ":"),
    ("Strichpunkt", ";"),
    ("Semikolon", ";"),
    ("Bindestrich", "-"),
    ("neue Zeile", "⏎"),
    ("neuer Absatz", "⏎"),
  ]

  /// Spoken token → punctuation it maps to. Lowercased keys; matched as WHOLE words only.
  /// Newline labels insert a line break; the rest attach to the preceding word. Derived from
  /// `punctuationReference` so there is exactly one source of truth.
  private static let punctuationMap: [(token: String, replacement: String)] =
    punctuationReference.map { entry in
      (entry.spoken.lowercased(), entry.symbol == "⏎" ? "\n" : entry.symbol)
    }

  /// Punctuation that must NOT have a leading space (it attaches to the preceding word).
  private static let attachingPunctuation: Set<Character> = [",", ".", "?", "!", ":", ";"]

  static func process(_ text: String, dictionary: DictationDictionary) -> String {
    guard !dictionary.isNoOp else { return text }

    var result = applyReplacements(text, replacements: dictionary.replacements)
    if dictionary.spokenPunctuationEnabled {
      result = applySpokenPunctuation(result)
    }
    return result
  }

  // MARK: - Literal replacements

  private static func applyReplacements(
    _ text: String, replacements: [DictationReplacement]
  ) -> String {
    var result = text
    for replacement in replacements {
      let from = replacement.from.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !from.isEmpty else { continue }
      let pattern =
        replacement.wholeWord
        ? "\\b\(NSRegularExpression.escapedPattern(for: from))\\b"
        : NSRegularExpression.escapedPattern(for: from)
      result = regexReplace(
        in: result, pattern: pattern, with: replacement.to, caseInsensitive: true)
    }
    return result
  }

  // MARK: - Spoken punctuation

  private static func applySpokenPunctuation(_ text: String) -> String {
    var result = text
    for entry in punctuationMap {
      let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.token))\\b"
      result = regexReplace(
        in: result, pattern: pattern, with: entry.replacement, caseInsensitive: true)
    }
    return tidyPunctuationSpacing(result)
  }

  /// Removes spaces before attaching punctuation and around newlines, then collapses runs of
  /// spaces/tabs to a single space. Newlines are preserved.
  private static func tidyPunctuationSpacing(_ text: String) -> String {
    var output = String()
    output.reserveCapacity(text.count)
    for character in text {
      if attachingPunctuation.contains(character) || character == "\n" {
        while output.last == " " || output.last == "\t" { output.removeLast() }
      }
      output.append(character)
    }
    return collapseInlineSpaces(output)
  }

  /// Collapses repeated spaces/tabs into one space without touching newlines, then trims.
  /// An inline space directly after a newline is dropped so a mapped line break starts clean.
  private static func collapseInlineSpaces(_ text: String) -> String {
    var output = String()
    output.reserveCapacity(text.count)
    var previousWasSpace = false
    var previousWasNewline = false
    for character in text {
      let isInlineSpace = character == " " || character == "\t"
      if isInlineSpace {
        if !previousWasSpace && !previousWasNewline { output.append(" ") }
        previousWasSpace = true
      } else {
        output.append(character)
        previousWasSpace = false
        previousWasNewline = character == "\n"
      }
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Regex helper

  private static func regexReplace(
    in text: String, pattern: String, with template: String, caseInsensitive: Bool
  ) -> String {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return text
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let escapedTemplate = NSRegularExpression.escapedTemplate(for: template)
    return regex.stringByReplacingMatches(
      in: text, options: [], range: range, withTemplate: escapedTemplate)
  }
}
