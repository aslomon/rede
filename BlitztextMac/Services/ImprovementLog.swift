import Foundation
import OSLog
import Observation

private let improvementLogger = Logger(subsystem: "app.rede.mac", category: "ImprovementLog")

// MARK: - Observation

/// A single learnable "Verbesserung" (MEM-2): what rede inserted vs. what the user left in the
/// field after editing. PRIVACY-SENSITIVE — recorded only with the opt-in improvement detection on
/// (a superset of the archive opt-in), stored on-device (0600), never sent anywhere. Holds the
/// before/after text so the overview can show the correction; not yet fed into any prompt.
struct ImprovementObservation: Codable, Identifiable, Sendable {
  let id: UUID
  let date: Date
  let appBundleID: String?
  let appName: String?
  /// `WorkflowType.rawValue` of the run whose paste this follows.
  let mode: String
  let inserted: String
  let finalText: String
  /// True when the user edited our text (`inserted != finalText`); false when left verbatim.
  let changed: Bool

  init(
    id: UUID = UUID(),
    date: Date,
    appBundleID: String?,
    appName: String?,
    mode: String,
    inserted: String,
    finalText: String,
    changed: Bool
  ) {
    self.id = id
    self.date = date
    self.appBundleID = appBundleID
    self.appName = appName
    self.mode = mode
    self.inserted = inserted
    self.finalText = finalText
    self.changed = changed
  }
}

// MARK: - Store

/// Bounded, on-device log of detected corrections. Mirrors `ContextLogStore`: own JSON file via
/// `AppSupportPaths`, written 0600, capped to the most recent entries. Opt-in (wired only while
/// improvement detection is enabled), so disabled == zero I/O.
@Observable
@MainActor
final class ImprovementLogStore {
  nonisolated static let maxEntries = 200
  /// Auto-expiry for this store. SHORTER than the 90-day archive on purpose: an observation holds
  /// the actual before/after TEXT (the most PII-heavy data in the app), so old corrections age out
  /// after a month even if the user never opens "Verlauf löschen".
  nonisolated static let retentionDays = 30

  /// Newest entries first.
  private(set) var observations: [ImprovementObservation] = []

  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileURL: URL = AppSupportPaths.improvementLogURL) {
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

  /// Appends an observation, prunes by age + count, then persists. Newest-first.
  func append(_ observation: ImprovementObservation) {
    observations.insert(observation, at: 0)
    prune()
    persist()
  }

  /// Removes everything and deletes the backing file ("Verlauf löschen").
  func clear() {
    observations = []
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Prunes age-expired entries NOW (not just on append/load), for the long-lived menu-bar process —
  /// so the retention backstop fires even across weeks of uptime. Persists only if something dropped.
  func pruneExpired() {
    let before = observations.count
    prune()
    if observations.count != before { persist() }
  }

  // MARK: - Persistence

  /// Drops observations older than `retentionDays`, then caps to the most recent `maxEntries`.
  /// Age-expiry is the privacy backstop so text-bearing corrections never linger indefinitely.
  private func prune() {
    if let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) {
      observations.removeAll { $0.date < cutoff }
    }
    if observations.count > Self.maxEntries {
      observations = Array(observations.prefix(Self.maxEntries))
    }
  }

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    guard let decoded = try? decoder.decode([ImprovementObservation].self, from: data) else {
      improvementLogger.error("Failed to decode improvement log; ignoring.")
      return
    }
    observations = decoded.sorted { $0.date > $1.date }
    prune()
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try encoder.encode(observations)
      try SecureFileWriter.write(data, to: fileURL)
    } catch {
      improvementLogger.error(
        "Failed to persist improvement log: \(error.localizedDescription, privacy: .public)")
    }
  }
}
