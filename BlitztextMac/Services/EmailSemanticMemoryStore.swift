import Foundation
import OSLog
import Observation

private let emailMemoryLogger = Logger(subsystem: "app.rede.mac", category: "EmailMemory")

struct EmailSemanticMemoryRecord: Codable, Identifiable, Sendable, Equatable {
  let id: UUID
  let date: Date
  let modeID: ModeConfig.ID
  let appBundleID: String?
  let appName: String?
  let windowTitle: String?
  let rawTranscript: String
  let finalText: String
  let embedding: [Double]
  let embeddingModel: String

  init(
    id: UUID = UUID(),
    date: Date,
    modeID: ModeConfig.ID,
    appBundleID: String?,
    appName: String?,
    windowTitle: String?,
    rawTranscript: String,
    finalText: String,
    embedding: [Double],
    embeddingModel: String
  ) {
    self.id = id
    self.date = date
    self.modeID = modeID
    self.appBundleID = appBundleID
    self.appName = appName
    self.windowTitle = windowTitle
    self.rawTranscript = rawTranscript
    self.finalText = finalText
    self.embedding = embedding
    self.embeddingModel = embeddingModel
  }
}

struct EmailSemanticMemorySnapshot: Codable, Sendable {
  var records: [EmailSemanticMemoryRecord]

  init(records: [EmailSemanticMemoryRecord] = []) {
    self.records = records
  }
}

@Observable
@MainActor
final class EmailSemanticMemoryStore {
  nonisolated static let maxEntries = 300
  nonisolated static let retentionDays = 30

  private(set) var snapshot: EmailSemanticMemorySnapshot

  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileURL: URL = AppSupportPaths.emailSemanticMemoryURL) {
    self.fileURL = fileURL
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
    self.snapshot = Self.loadSnapshot(from: fileURL, decoder: decoder)
    prune()
  }

  var records: [EmailSemanticMemoryRecord] {
    snapshot.records
  }

  func append(_ record: EmailSemanticMemoryRecord) {
    guard !record.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    guard !record.embedding.isEmpty else { return }
    snapshot.records.removeAll { $0.id == record.id }
    snapshot.records.insert(record, at: 0)
    prune()
    persist()
  }

  func clear() {
    snapshot = EmailSemanticMemorySnapshot()
    try? FileManager.default.removeItem(at: fileURL)
  }

  private func prune(now: Date = Date()) {
    let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now)
    if let cutoff {
      snapshot.records.removeAll { $0.date < cutoff }
    }
    snapshot.records.sort { $0.date > $1.date }
    if snapshot.records.count > Self.maxEntries {
      snapshot.records = Array(snapshot.records.prefix(Self.maxEntries))
    }
  }

  private static func loadSnapshot(
    from url: URL,
    decoder: JSONDecoder
  ) -> EmailSemanticMemorySnapshot {
    guard let data = try? Data(contentsOf: url) else { return EmailSemanticMemorySnapshot() }
    if let snapshot = try? decoder.decode(EmailSemanticMemorySnapshot.self, from: data) {
      return snapshot
    }
    if let legacyRecords = try? decoder.decode([EmailSemanticMemoryRecord].self, from: data) {
      return EmailSemanticMemorySnapshot(records: legacyRecords)
    }
    emailMemoryLogger.error("Failed to decode semantic email memory; starting empty.")
    return EmailSemanticMemorySnapshot()
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try encoder.encode(snapshot)
      try SecureFileWriter.write(data, to: fileURL)
    } catch {
      emailMemoryLogger.error(
        "Failed to persist semantic email memory: \(error.localizedDescription, privacy: .public)")
    }
  }
}
