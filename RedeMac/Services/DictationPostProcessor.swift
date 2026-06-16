import Foundation

/// Pure, on-device, deterministic post-processing of a cleaned transcript BEFORE rewrite/paste:
/// literal replacements (case-insensitive match; whole-word vs substring; the user's `to` casing).
///
/// Fully unit-testable: no I/O, no actor, no `AppState` dependency.
enum DictationPostProcessor {

  static func process(_ text: String, dictionary: DictationDictionary) -> String {
    guard !dictionary.isNoOp else { return text }
    return applyReplacements(text, replacements: dictionary.replacements)
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
