import Foundation
import OSLog
import Observation

private let archiveLogger = Logger(subsystem: "app.rede.mac", category: "Archive")

// MARK: - Archive entry

/// A persisted, text-only record of a single completed run (Phase 4a). No audio.
/// For plain transcription `rawTranscript == finalText`.
struct ArchiveEntry: Codable, Identifiable, Sendable {
  let id: UUID
  let date: Date
  let mode: WorkflowType
  let modeID: ModeConfig.ID?
  let modeName: String?
  let rawTranscript: String
  let finalText: String
  let backend: TranscriptionBackend
  let durationSec: Double

  init(
    id: UUID = UUID(),
    date: Date,
    mode: WorkflowType,
    modeID: ModeConfig.ID? = nil,
    modeName: String? = nil,
    rawTranscript: String,
    finalText: String,
    backend: TranscriptionBackend,
    durationSec: Double
  ) {
    self.id = id
    self.date = date
    self.mode = mode
    self.modeID = modeID
    self.modeName = modeName
    self.rawTranscript = rawTranscript
    self.finalText = finalText
    self.backend = backend
    self.durationSec = durationSec
  }

  init(record: ArchiveRunRecord) {
    self.init(
      date: record.date,
      mode: record.mode,
      modeID: record.modeID,
      modeName: record.modeName,
      rawTranscript: record.rawTranscript,
      finalText: record.finalText,
      backend: record.backend,
      durationSec: record.durationSec
    )
  }
}

// MARK: - Archive store

/// Text-first transcription archive. Bounded ring (~200 entries) + 90-day retention.
/// Opt-in (`AppSettings.archiveEnabled`); when disabled it is never wired, so zero I/O.
/// Files are written 0600 and remain purgeable on demand.
@Observable
@MainActor
final class ArchiveStore {
  nonisolated static let maxEntries = 200
  nonisolated static let retentionDays = 90

  /// Newest entries first.
  private(set) var entries: [ArchiveEntry] = []

  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileURL: URL = AppSupportPaths.archiveURL) {
    self.fileURL = fileURL
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
    load()
  }

  // MARK: - Mutations

  /// Appends a run, prunes by age + count, then persists. Newest-first ordering.
  func append(_ record: ArchiveRunRecord) {
    let entry = ArchiveEntry(record: record)
    entries.insert(entry, at: 0)
    prune()
    persist()
  }

  func delete(_ id: ArchiveEntry.ID) {
    entries.removeAll { $0.id == id }
    persist()
  }

  /// Removes everything and deletes the backing file (privacy "Archiv löschen").
  func clear() {
    entries = []
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Entries grouped by calendar day (newest day first), for a day-list UI.
  func entriesByDay(calendar: Calendar = .current) -> [(day: Date, entries: [ArchiveEntry])] {
    let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
    return
      groups
      .map { (day: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
      .sorted { $0.day > $1.day }
  }

  // MARK: - Persistence

  private func prune() {
    let cutoff = Calendar.current.date(
      byAdding: .day, value: -Self.retentionDays, to: Date())
    if let cutoff {
      entries.removeAll { $0.date < cutoff }
    }
    if entries.count > Self.maxEntries {
      entries = Array(entries.prefix(Self.maxEntries))
    }
  }

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    guard let decoded = try? decoder.decode([ArchiveEntry].self, from: data) else {
      archiveLogger.error("Failed to decode archive history; ignoring.")
      return
    }
    entries = decoded.sorted { $0.date > $1.date }
    prune()
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try encoder.encode(entries)
      try SecureFileWriter.write(data, to: fileURL)
    } catch {
      archiveLogger.error(
        "Failed to persist archive: \(error.localizedDescription, privacy: .public)")
    }
  }
}
