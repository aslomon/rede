import Foundation

// MARK: - Dictation Dictionary
//
// On-device, deterministic post-processing of a transcript BEFORE rewrite/paste: fixed from→to
// literal replacements (`replacements`) the user maintains, applied in `DictationPostProcessor`.
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

/// The user-maintained dictionary of literal from→to replacements.
struct DictationDictionary: Codable, Sendable, Hashable {
  var replacements: [DictationReplacement]

  init(replacements: [DictationReplacement] = []) {
    self.replacements = replacements
  }

  enum CodingKeys: String, CodingKey {
    case replacements
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Older files may still carry a `spokenPunctuationEnabled` key; JSONDecoder ignores it.
    replacements =
      try container.decodeIfPresent([DictationReplacement].self, forKey: .replacements) ?? []
  }

  /// True when there is genuinely nothing to do: no usable replacements.
  /// `DictationPostProcessor` guards on this so an unconfigured dictionary adds zero overhead.
  var isNoOp: Bool {
    replacements.allSatisfy { $0.from.isEmpty }
  }
}
