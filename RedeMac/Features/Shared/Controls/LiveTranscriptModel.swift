import Foundation

/// Presentation logic for the live row in the recording pill. Pure; the view only renders it.
///
/// Live text is display-only and non-monotonic (provisional text may be replaced), so the pill
/// never assumes prefix stability: it shows the tail of the current text, anchored at a word
/// start so the window moves word by word rather than character by character.
struct LiveTranscriptModel: Equatable {
  enum Note: Equatable {
    case connecting
    case listening
    case finishing
    /// Live stopped; the recording is transcribed normally afterwards. Not an error.
    case fallsBackToRecording
  }

  struct Tail: Equatable {
    var stable: String
    var provisional: String
    /// True when earlier text was cut off at the left ("… ").
    var isTruncated: Bool
    var isEmpty: Bool { stable.isEmpty && provisional.isEmpty }
  }

  static let tailLimit = 96

  let snapshot: LiveTranscriptSnapshot?
  let state: LiveDisplayState?

  init(snapshot: LiveTranscriptSnapshot?, state: LiveDisplayState?) {
    self.snapshot = snapshot
    self.state = state
  }

  var isVisible: Bool { state != nil }

  var note: Note? {
    guard let state else { return nil }
    switch state {
    case .connecting: return .connecting
    case .streaming: return tail.isEmpty ? .listening : nil
    case .finishing: return .finishing
    case .failed: return .fallsBackToRecording
    }
  }

  var tail: Tail {
    guard state != nil, let snapshot else {
      return Tail(stable: "", provisional: "", isTruncated: false)
    }
    return Self.tail(stable: snapshot.stableText, provisional: snapshot.provisionalText)
  }

  /// VoiceOver must not announce every delta while recording: the value is constant while
  /// streaming and only carries the text once live has finished.
  var accessibilityValue: String {
    switch state {
    case .streaming, .connecting: return "läuft"
    case .finishing, .failed, .none:
      let text = tail
      return [text.stable, text.provisional].filter { !$0.isEmpty }.joined(separator: " ")
    }
  }

  // MARK: - Tail

  static func tail(stable: String, provisional: String) -> Tail {
    let separator = (stable.isEmpty || provisional.isEmpty) ? "" : " "
    let combined = Array(stable + separator + provisional)
    guard combined.count > tailLimit else {
      return Tail(stable: stable, provisional: provisional, isTruncated: false)
    }
    var start = combined.count - tailLimit
    if let space = combined[start...].firstIndex(of: " "), space + 1 < combined.count {
      start = space + 1
    }
    let stableCount = stable.count
    let stableTail = start < stableCount ? String(combined[start..<stableCount]) : ""
    let provisionalStart = max(start, stableCount + separator.count)
    let provisionalTail =
      provisionalStart < combined.count ? String(combined[provisionalStart...]) : ""
    return Tail(stable: stableTail, provisional: provisionalTail, isTruncated: true)
  }
}
