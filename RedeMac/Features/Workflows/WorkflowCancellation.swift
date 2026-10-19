import Foundation

/// User cancel is terminal for the whole pipeline: no fallback, no retry, no paste, no archive and
/// no error UI. A timeout is NOT a cancel and keeps its normal fallback.
enum WorkflowCancellation {
  /// True when `error` (or the surrounding task) means "the user stopped this run".
  static func isTerminal(_ error: Error) -> Bool {
    Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
  }
}

/// Identity of the current run. Every async result is checked against it before it may touch
/// state, so a result that finishes after Esc/reset is dropped instead of pasted or archived.
@MainActor
final class WorkflowRunTracker {
  private(set) var current: UUID?

  /// Starts a new run; any earlier run becomes stale.
  func begin() -> UUID {
    let id = UUID()
    current = id
    return id
  }

  /// Marks every in-flight run stale (user cancel, reset, new start).
  func invalidate() { current = nil }

  func isCurrent(_ id: UUID) -> Bool { current == id }
}
