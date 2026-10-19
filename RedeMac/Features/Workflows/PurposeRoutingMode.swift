import Foundation

/// Per-mode "Automatik" switch. This is a per-mode OPTION, never a workflow slot: it cannot change
/// which mode a hotkey selects. Unknown or malformed stored values decode to `.off`, so a settings
/// file written by a different build can never switch routing on by accident.
enum PurposeRoutingMode: String, Codable, Sendable, CaseIterable, Identifiable {
  case off
  case automatic

  var id: String { rawValue }

  init(from decoder: Decoder) throws {
    let raw = try? decoder.singleValueContainer().decode(String.self)
    self = raw.flatMap(PurposeRoutingMode.init(rawValue:)) ?? .off
  }

  var isAutomatic: Bool { self == .automatic }
}

extension ModeKind {
  /// Kinds whose output passes through a rewrite and so can take a purpose overlay: free-form
  /// rewrite and emoji (Social). Plain dictation has no rewrite step, so it is never routed.
  /// The overlay is appended after the whole mode prompt and states that the mode's tone and
  /// emoji settings win, so Social keeps its voice. Exhaustive: a new kind must decide here.
  var rewritesText: Bool {
    switch self {
    case .transcribeOnly: return false
    case .transcribeThenRewrite, .transcribeThenEmoji: return true
    }
  }
}
