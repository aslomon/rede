import CryptoKit
import Foundation
import OSLog
import Observation

private let coordinatorLogger = Logger(
  subsystem: "app.rede.mac", category: "MemoryCoordinator")

/// Drives the two-speed Memory cadence (docs/MEMORY-spezifikation.md):
/// - per-run incremental fold off the main actor (`Task.detached(.utility)`), never blocking,
/// - a daily decay/prune pass,
/// - a manual full recompute over the archive, which can auto-promote recurring domain terms,
/// - app-launch catch-up gated by an archive content hash.
///
/// Candidate computation is conservative: recurring names/foreign terms auto-promote after two
/// documents, generic domain terms after three; denylist/manual removal always wins.
@Observable
@MainActor
final class MemoryCoordinator {
  /// True while a full recompute / catch-up is running, for UI ("Analysieren…").
  private(set) var isRecomputing = false
  private(set) var lastDailyPassDay: Date?

  private let memory: MemoryStore
  private let archive: ArchiveStore
  private let extractor: MemoryExtractionService

  init(
    memory: MemoryStore,
    archive: ArchiveStore,
    extractor: MemoryExtractionService = MemoryExtractionService()
  ) {
    self.memory = memory
    self.archive = archive
    self.extractor = extractor
  }

  // MARK: - Per-run incremental fold (background, non-blocking)

  /// Folds ONE raw transcript into the candidate index off the main actor.
  /// Safe to call on every run; returns immediately.
  func ingest(rawTranscript: String, date: Date = Date()) {
    let text = rawTranscript
    let extractor = self.extractor
    Task.detached(priority: .utility) {
      let extracted = await extractor.extract(from: text)
      guard !extracted.isEmpty else { return }
      await MainActor.run {
        self.memory.fold(extracted: extracted, at: date)
      }
    }
  }

  // MARK: - Daily decay/prune

  /// Runs the decay/prune pass at most once per calendar day.
  func runDailyPassIfNeeded(now: Date = Date()) {
    let today = Calendar.current.startOfDay(for: now)
    if let last = lastDailyPassDay, Calendar.current.isDate(last, inSameDayAs: today) {
      return
    }
    lastDailyPassDay = today
    memory.decayAndPrune(now: now)
  }

  // MARK: - Manual full recompute

  /// Full pass over the entire archive ("Jetzt analysieren"). Rebuilds the candidate index and
  /// auto-promotes recurring domain terms. Existing learned terms/denylist are preserved.
  /// Extraction runs off the main actor.
  func recomputeMemory() async {
    guard !isRecomputing else { return }
    isRecomputing = true
    defer { isRecomputing = false }

    let entries = archive.entries
    guard !entries.isEmpty else {
      memory.replaceCandidates([], dates: [])
      memory.updateWatermark(contentHash: Self.contentHash(of: []))
      return
    }

    let transcripts = entries.map { $0.rawTranscript }
    let dates = entries.map { $0.date }
    let extractor = self.extractor
    let contentHash = Self.contentHash(of: transcripts)

    let extractedPerDoc: [[ExtractedTerm]] = await Task.detached(priority: .utility) {
      var perDoc: [[ExtractedTerm]] = []
      perDoc.reserveCapacity(transcripts.count)
      for transcript in transcripts {
        perDoc.append(await extractor.extract(from: transcript))
      }
      return perDoc
    }.value

    memory.replaceCandidates(extractedPerDoc, dates: dates)
    memory.updateWatermark(contentHash: contentHash)
  }

  // MARK: - App-launch catch-up (mtime/hash gated)

  /// On launch, recompute only when the archive content changed since the last watermark.
  /// Cheap no-op when nothing changed (the central reason to hash the archive).
  func catchUpIfNeeded() async {
    let transcripts = archive.entries.map { $0.rawTranscript }
    let contentHash = Self.contentHash(of: transcripts)
    guard !memory.isUpToDate(with: contentHash) else {
      coordinatorLogger.debug("Memory catch-up skipped; archive unchanged.")
      return
    }
    await recomputeMemory()
  }

  // MARK: - Hashing

  /// Stable content hash over the raw transcripts; gates catch-up + records the watermark.
  static func contentHash(of transcripts: [String]) -> String {
    var hasher = SHA256()
    hasher.update(data: Data("\(transcripts.count)\u{0}".utf8))
    for transcript in transcripts {
      hasher.update(data: Data(transcript.utf8))
      hasher.update(data: Data([0]))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
