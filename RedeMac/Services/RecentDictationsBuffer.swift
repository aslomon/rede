import Foundation
import Observation

struct RecentDictation: Identifiable, Sendable {
  let id: UUID
  let date: Date
  let mode: WorkflowType
  let modeName: String?
  let finalText: String

  init(
    id: UUID = UUID(),
    date: Date,
    mode: WorkflowType,
    modeName: String? = nil,
    finalText: String
  ) {
    self.id = id
    self.date = date
    self.mode = mode
    self.modeName = modeName
    self.finalText = finalText
  }
}

/// RAM-only recent dictations buffer. Session-only by design, cleared when the app quits,
/// deliberately a smaller privacy footprint than the system clipboard the same text already sits
/// on; secure-field runs are excluded by the caller (AppState guard). No file I/O or persistence
/// lives here.
@Observable
@MainActor
final class RecentDictationsBuffer {
  nonisolated static let cap = 3

  /// Newest items first.
  private(set) var items: [RecentDictation] = []

  func record(_ item: RecentDictation) {
    let trimmedText = item.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return }

    items.insert(item, at: 0)
    if items.count > Self.cap {
      items = Array(items.prefix(Self.cap))
    }
  }

  func clear() {
    items = []
  }
}

extension RecentDictationsBuffer {
  /// Pure source switch for the popover "letzte diktate" section: the persisted archive (newest
  /// first) while archiving is enabled, else the RAM session items — both capped at `cap`.
  /// Static + pure so the privacy-relevant switch is unit-testable without an `AppState`.
  nonisolated static func displayed(
    archiveEnabled: Bool,
    archived: [RecentDictation],
    session: [RecentDictation]
  ) -> [RecentDictation] {
    archiveEnabled ? Array(archived.prefix(cap)) : Array(session.prefix(cap))
  }
}

extension RecentDictation {
  /// Maps a completed run into a session-buffer item — or nil when the run targeted a
  /// secure/password field and must leave no trace, not even in RAM. THE single gate for RAM
  /// retention; pure so the privacy rule is unit-testable.
  static func bufferItem(
    from record: ArchiveRunRecord,
    isSecureFieldTarget: Bool
  ) -> RecentDictation? {
    guard !isSecureFieldTarget else { return nil }
    return RecentDictation(
      date: record.date,
      mode: record.mode,
      modeName: record.modeName,
      finalText: record.finalText
    )
  }
}
