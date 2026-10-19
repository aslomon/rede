import Foundation
import Observation

/// The part of the live controller a workflow depends on. A seam, not a second implementation:
/// `LiveTranscriptionController` conforms as-is, tests supply a scripted fake.
@MainActor
protocol LiveSessionControlling: AnyObject {
  var snapshot: LiveTranscriptSnapshot { get }
  var phase: LiveTranscriptionController.Phase { get }
  func begin(_ configuration: LiveConfiguration)
  func finish() async -> LiveOutcome
  func cancel()
}

extension LiveTranscriptionController: LiveSessionControlling {}

/// One shared helper for every remote-transcription workflow (no per-workflow copies).
///
/// Live is display-only while speaking: the text is never typed anywhere. Its final text replaces
/// the file transcription only when the session completed cleanly; any unusable outcome (failure,
/// timeout, empty text) means the existing file path runs on the local recording, with no mixing.
@MainActor
@Observable
final class WorkflowLiveSupport {
  private let makeSession: @MainActor () -> any LiveSessionControlling
  private var session: (any LiveSessionControlling)?

  init(makeSession: @escaping @MainActor () -> any LiveSessionControlling) {
    self.makeSession = makeSession
  }

  /// What the pill shows while speaking. Nil before a session exists.
  var snapshot: LiveTranscriptSnapshot? { session?.snapshot }

  /// Coarse display state for the pill; nil when there is nothing to show.
  var displayState: LiveDisplayState? { session.flatMap { LiveDisplayState(phase: $0.phase) } }

  /// Opens a fresh session. Never throws and never blocks recording: failures land in the
  /// controller's phase and surface later as an unusable outcome.
  func begin(language: String, keywords: [String]) {
    session?.cancel()
    let session = makeSession()
    self.session = session
    var configuration = LiveConfiguration()
    configuration.language = language
    configuration.keywords = keywords
    session.begin(configuration)
  }

  /// The final live text, or nil when the file transcription must run. Throws
  /// `CancellationError` when the session was cancelled: that is terminal for the whole run.
  func finalTranscript() async throws -> String? {
    guard let session else { return nil }
    switch await session.finish() {
    case .transcript(let text, _):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    case .unusable:
      return nil
    case .cancelled:
      throw CancellationError()
    }
  }

  /// Idempotent. Closes the socket and drops buffers immediately.
  func cancel() {
    session?.cancel()
  }
}

/// The remote-access wiring every remote-capable workflow receives from the composition root.
/// The defaults fail CLOSED: a workflow built without it cannot reach OpenAI.
struct WorkflowRemoteContext {
  /// Evaluated by the OpenAI clients once per HTTP attempt.
  var isRemoteAllowed: @Sendable () -> Bool = { false }
  /// Non-nil only when live transcription is opted in AND available for this run.
  var live: WorkflowLiveSupport?
}

/// What the live part of the pill is doing. Derived from the controller phase; `finished` and
/// `cancelled` show nothing because the pill has moved on to processing (or the run is over).
enum LiveDisplayState: Equatable, Sendable {
  case connecting
  case streaming
  case finishing
  case failed(LiveFailure)

  init?(phase: LiveTranscriptionController.Phase) {
    switch phase {
    case .idle, .finished, .cancelled: return nil
    case .connecting: self = .connecting
    case .streaming: self = .streaming
    case .finishing: self = .finishing
    case .failed(let failure): self = .failed(failure)
    }
  }
}
