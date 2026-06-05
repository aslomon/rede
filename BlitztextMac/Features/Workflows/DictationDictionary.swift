import Foundation

// MARK: - Dictation Dictionary
//
// On-device, deterministic post-processing of a transcript BEFORE rewrite/paste. Two parts:
//  1. Literal replacements (`replacements`): fixed from→to substitutions the user maintains.
//  2. Spoken punctuation (`spokenPunctuationEnabled`): mapping standalone spoken tokens such as
//     "Komma" or "neue Zeile" to their punctuation. Both run in `DictationPostProcessor`.
//
// Codable + Sendable so it persists inside `AppSettings` and crosses actor boundaries cleanly.

/// A single literal replacement applied to the transcript.
/// `wholeWord` true → matches only on word boundaries; false → matches as a substring.
struct DictationReplacement: Codable, Sendable, Hashable, Identifiable {
  /// Stable identity for SwiftUI lists. Not persisted — re-derived from `from`/`to` on decode.
  var id: UUID = UUID()
  var from: String
  var to: String
  var wholeWord: Bool

  init(from: String, to: String, wholeWord: Bool = true, id: UUID = UUID()) {
    self.id = id
    self.from = from
    self.to = to
    self.wholeWord = wholeWord
  }

  enum CodingKeys: String, CodingKey {
    case from
    case to
    case wholeWord
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = UUID()
    from = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
    to = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
    wholeWord = try container.decodeIfPresent(Bool.self, forKey: .wholeWord) ?? true
  }
}

/// The full user-maintained dictionary: literal replacements plus the spoken-punctuation toggle.
struct DictationDictionary: Codable, Sendable, Hashable {
  var replacements: [DictationReplacement]
  var spokenPunctuationEnabled: Bool

  init(replacements: [DictationReplacement] = [], spokenPunctuationEnabled: Bool = false) {
    self.replacements = replacements
    self.spokenPunctuationEnabled = spokenPunctuationEnabled
  }

  enum CodingKeys: String, CodingKey {
    case replacements
    case spokenPunctuationEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    replacements =
      try container.decodeIfPresent([DictationReplacement].self, forKey: .replacements) ?? []
    spokenPunctuationEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .spokenPunctuationEnabled) ?? false
  }

  /// True when there is genuinely nothing to do: no replacements AND punctuation mapping off.
  /// `DictationPostProcessor` guards on this so an unconfigured dictionary adds zero overhead.
  var isNoOp: Bool {
    !spokenPunctuationEnabled && replacements.allSatisfy { $0.from.isEmpty }
  }
}
