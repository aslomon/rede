import AppKit

/// Optional audio feedback for dictation. Eyes-off background-hotkey use benefits from an audible
/// cue: a soft "Tink" when recording starts, a bright "Glass" when the text is ready, and a low
/// "Basso" on error. Uses the built-in macOS system sounds (no bundled assets) and is a no-op when
/// the named sound is unavailable. Gated by the user's `soundFeedbackEnabled` opt-in at the call site.
@MainActor
enum EarconPlayer {

  /// The dictation moments worth an audible cue.
  enum Event {
    case start
    case done
    case error

    /// A built-in macOS system sound name (files live in /System/Library/Sounds). Chosen so the
    /// three events are easy to tell apart by ear: rising for start, bright for done, low for error.
    var systemSoundName: String {
      switch self {
      case .start: return "Tink"
      case .done: return "Glass"
      case .error: return "Basso"
      }
    }
  }

  /// Plays the earcon for `event`. Best-effort: an unknown sound name simply produces no sound.
  /// A fresh `NSSound` per call so rapid successive events don't cut each other off mid-play.
  static func play(_ event: Event) {
    NSSound(named: event.systemSoundName)?.play()
  }
}
