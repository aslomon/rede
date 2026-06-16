import Foundation
import OSLog
import Observation

private let memoryLogger = Logger(subsystem: "app.rede.mac", category: "Memory")

// MARK: - Memory model

/// The kind of personal-vocabulary term, used both for scoring/ordering and for the
/// structured LLM block. `name` + `foreign` are prioritized for the Whisper hint.
enum MemoryCategory: String, Codable, Sendable, CaseIterable {
  case name
  case foreign
  case term

  /// Whisper injection priority (lower sorts first; names+foreign before generic terms).
  var injectionRank: Int {
    switch self {
    case .name: return 0
    case .foreign: return 1
    case .term: return 2
    }
  }

  var displayName: String {
    switch self {
    case .name: return "Namen"
    case .foreign: return "Fremdwörter"
    case .term: return "Fachbegriffe"
    }
  }
}

/// A computed vocabulary candidate. Persisted in the candidate index and folded incrementally per
/// run. Strong recurring candidates are auto-promoted to `confirmed`; the visible suggestions list
/// remains a review surface for lower-confidence items.
struct MemoryCandidate: Codable, Identifiable, Sendable {
  var id: String { lemma.lowercased() }
  var lemma: String
  var surfaceForm: String
  var category: MemoryCategory
  var docFrequency: Int
  var lastSeen: Date
  var score: Double

  init(
    lemma: String,
    surfaceForm: String,
    category: MemoryCategory,
    docFrequency: Int = 1,
    lastSeen: Date = Date(),
    score: Double = 0
  ) {
    self.lemma = lemma
    self.surfaceForm = surfaceForm
    self.category = category
    self.docFrequency = docFrequency
    self.lastSeen = lastSeen
    self.score = score
  }
}

/// A learned or manually confirmed term. This — plus the user's global `customTerms` — is what
/// gets injected as vocabulary.
struct MemoryConfirmedTerm: Codable, Identifiable, Sendable, Hashable {
  var id: String { term.lowercased() }
  var term: String
  /// The base (lemma) form this confirmation came from. Used to dedupe suggestions, which are keyed
  /// by lemma — otherwise an inflected confirmation (surfaceForm "Herrn" / lemma "Herr") keeps
  /// reappearing as a candidate. Optional so legacy memory.json files decode (missing key → nil).
  var lemma: String?
  var category: MemoryCategory
  var addedAt: Date

  init(term: String, lemma: String? = nil, category: MemoryCategory, addedAt: Date = Date()) {
    self.term = term
    self.lemma = lemma
    self.category = category
    self.addedAt = addedAt
  }
}

/// The processing watermark used to gate app-launch catch-up (skip when archive unchanged).
struct MemoryWatermark: Codable, Sendable {
  var contentHash: String
  var date: Date
}

/// On-disk shape (`memory.json`). Separate from settings.json, 0600, opt-in.
struct MemorySnapshot: Codable, Sendable {
  var candidates: [MemoryCandidate]
  var confirmed: [MemoryConfirmedTerm]
  var denylist: [String]
  var lastProcessed: MemoryWatermark?

  init(
    candidates: [MemoryCandidate] = [],
    confirmed: [MemoryConfirmedTerm] = [],
    denylist: [String] = [],
    lastProcessed: MemoryWatermark? = nil
  ) {
    self.candidates = candidates
    self.confirmed = confirmed
    self.denylist = denylist
    self.lastProcessed = lastProcessed
  }
}

/// What the rewrite prompt consumes: confirmed terms split into the three categories.
struct MemoryContext: Sendable {
  var names: [String]
  var terms: [String]
  var foreign: [String]

  var isEmpty: Bool { names.isEmpty && terms.isEmpty && foreign.isEmpty }
}

// MARK: - Memory store

/// Two-speed Memory (see docs/MEMORY-spezifikation.md):
/// candidate computation (frequent, background, incremental) is decoupled from prompt injection.
/// Recurring domain terms auto-promote into the confirmed vocabulary; denylist/manual removal still
/// wins and prevents re-adding noisy terms.
@Observable
@MainActor
final class MemoryStore {
  /// Whisper hint hard cap (224-token budget; best terms go LAST in the joined string). Kept small
  /// on purpose: a long prefill prompt makes some Whisper models (large-v3) emit nothing, and the
  /// user only wants a focused handful of learned terms — not hundreds.
  nonisolated static let injectionCap = 30
  /// Hard cap on auto-LEARNED terms kept on disk. Stops the learned vocabulary from growing without
  /// bound; the weakest (lowest-ranked) terms are pruned once the cap is exceeded.
  nonisolated static let maxConfirmed = 30
  /// Per-category cap for the LLM block to avoid prompt bloat.
  nonisolated static let llmBlockPerCategoryCap = 12
  /// Candidate index soft cap (decay/prune keeps it bounded).
  nonisolated static let maxCandidates = 500
  nonisolated static let retentionDays = 90
  /// Minimum cross-document frequency before a candidate surfaces as a suggestion.
  nonisolated static let suggestionMinDocFrequency = 2
  /// Auto vocabulary thresholds: names/foreign words are usually distinctive after two separate
  /// appearances; generic terms need a third document to avoid normal nouns.
  nonisolated static let autoConfirmNameOrForeignDocFrequency = 2
  nonisolated static let autoConfirmTermDocFrequency = 3

  /// Conservative guardrail against normal function/business words becoming vocabulary just
  /// because they recur. Normalized keys come from 200+ German words, 200+ English words and a
  /// small app-specific noise list.
  nonisolated static let commonTermDenylist: Set<String> = MemoryCommonWords.all

  private(set) var snapshot: MemorySnapshot

  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileURL: URL = AppSupportPaths.memoryURL) {
    self.fileURL = fileURL
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
    self.snapshot = Self.loadSnapshot(from: fileURL, decoder: decoder)
  }

  // MARK: - Read-only views

  var candidates: [MemoryCandidate] { snapshot.candidates }
  var confirmed: [MemoryConfirmedTerm] { snapshot.confirmed }
  var denylist: [String] { snapshot.denylist }
  var lastProcessed: MemoryWatermark? { snapshot.lastProcessed }

  /// Suggestions surfaced in the archive UI: scored candidates, recurring, not yet
  /// confirmed and not denied. Highest score first.
  var suggestions: [MemoryCandidate] {
    let confirmedIDs = Set(snapshot.confirmed.map { $0.id })
    // Candidates are keyed by lemma; learned terms store the (possibly inflected) surface form, so
    // also dedupe against learned LEMMAs to stop an already-learned term reappearing.
    let confirmedLemmas = Set(snapshot.confirmed.compactMap { $0.lemma?.lowercased() })
    let denied = Set(snapshot.denylist.map { $0.lowercased() })
    return
      snapshot.candidates
      .filter {
        $0.docFrequency >= Self.suggestionMinDocFrequency
          && !confirmedIDs.contains($0.id)
          && !confirmedLemmas.contains($0.lemma.lowercased())
          && !denied.contains($0.lemma.lowercased())
      }
      .sorted { $0.score > $1.score }
  }

  /// The confirmed terms split into the three categories for the LLM block.
  var context: MemoryContext {
    var names: [String] = []
    var terms: [String] = []
    var foreign: [String] = []
    for confirmedTerm in snapshot.confirmed {
      switch confirmedTerm.category {
      case .name: names.append(confirmedTerm.term)
      case .term: terms.append(confirmedTerm.term)
      case .foreign: foreign.append(confirmedTerm.term)
      }
    }
    return MemoryContext(
      names: Array(names.prefix(Self.llmBlockPerCategoryCap)),
      terms: Array(terms.prefix(Self.llmBlockPerCategoryCap)),
      foreign: Array(foreign.prefix(Self.llmBlockPerCategoryCap))
    )
  }

  /// Confirmed memory terms, ranked (rarity × recency-weighted docFrequency), names+foreign
  /// first, capped to the Whisper hint budget. Caller appends these AFTER the user's own terms.
  func rankedInjectionTerms(limit: Int = MemoryStore.injectionCap) -> [String] {
    // Join confirmed terms to their candidate stats (if available) for ranking.
    let candidatesByID = Dictionary(
      snapshot.candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let ranked =
      snapshot.confirmed
      .sorted { lhs, rhs in
        if lhs.category.injectionRank != rhs.category.injectionRank {
          return lhs.category.injectionRank < rhs.category.injectionRank
        }
        let lhsScore = candidatesByID[lhs.id]?.score ?? 0
        let rhsScore = candidatesByID[rhs.id]?.score ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.addedAt > rhs.addedAt
      }
      .map { $0.term }
    // Keep the highest-priority terms under the cap, then REVERSE so the most important
    // land LAST in the joined hint — Whisper drops the earliest tokens on overflow.
    return Array(ranked.prefix(limit)).reversed()
  }

  // MARK: - Curation (changes the INJECTED set)

  /// Promote a candidate (or arbitrary term) into the learned/injected set.
  func confirm(_ candidate: MemoryCandidate) {
    confirm(term: candidate.surfaceForm, lemma: candidate.lemma, category: candidate.category)
  }

  func confirm(term: String, category: MemoryCategory) {
    confirm(term: term, lemma: term, category: category)
  }

  func confirm(term: String, lemma: String, category: MemoryCategory) {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let entry = MemoryConfirmedTerm(
      term: trimmed,
      lemma: lemma.trimmingCharacters(in: .whitespacesAndNewlines),
      category: category
    )
    if !snapshot.confirmed.contains(where: { $0.id == entry.id }) {
      snapshot.confirmed.append(entry)
    }
    // Re-confirming a previously denied term clears it from the denylist.
    snapshot.denylist.removeAll { $0.lowercased() == trimmed.lowercased() }
    persist()
  }

  /// Remove a learned term without denylisting it. UI removal should usually call `deny(term:)`.
  func unconfirm(_ id: MemoryConfirmedTerm.ID) {
    snapshot.confirmed.removeAll { $0.id == id }
    persist()
  }

  /// Deny a term: remove it from confirmed + candidates and ensure it never returns.
  func deny(term: String) {
    let lower = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !lower.isEmpty else { return }
    snapshot.confirmed.removeAll { $0.term.lowercased() == lower }
    snapshot.candidates.removeAll { $0.lemma.lowercased() == lower }
    if !snapshot.denylist.contains(where: { $0.lowercased() == lower }) {
      snapshot.denylist.append(term.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    persist()
  }

  func deny(_ candidate: MemoryCandidate) {
    deny(term: candidate.lemma)
  }

  /// Wipes every persisted memory artifact (privacy: "Memory löschen").
  func clear() {
    snapshot = MemorySnapshot()
    try? FileManager.default.removeItem(at: fileURL)
  }

  // MARK: - Candidate computation (NEVER auto-promotes to injection)

  /// Incremental fold of ONE document's extracted terms into the candidate index.
  /// Denied terms are dropped. Existing candidates accumulate frequency + recency.
  func fold(extracted: [ExtractedTerm], at date: Date = Date()) {
    guard !extracted.isEmpty else { return }
    let denied = Set(snapshot.denylist.map { $0.lowercased() })
    var index = Dictionary(
      snapshot.candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    for term in extracted {
      let key = term.lemma.lowercased()
      guard !denied.contains(key) else { continue }
      if var existing = index[key] {
        existing.docFrequency += 1
        existing.lastSeen = max(existing.lastSeen, date)
        existing.surfaceForm = term.surfaceForm
        // A name/foreign vote upgrades a generic term in a stable, deterministic way.
        if term.category.injectionRank < existing.category.injectionRank {
          existing.category = term.category
        }
        index[key] = existing
      } else {
        index[key] = MemoryCandidate(
          lemma: term.lemma,
          surfaceForm: term.surfaceForm,
          category: term.category,
          docFrequency: 1,
          lastSeen: date
        )
      }
    }

    snapshot.candidates = Array(index.values)
    rescore(now: date)
    autoConfirmRecurringCandidates()
    persist()
  }

  /// Daily decay + prune: ages out stale candidates (90-day window) and bounds the index.
  /// Does NOT touch learned terms/denylist — the injected set is unaffected.
  func decayAndPrune(now: Date = Date()) {
    let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now)
    if let cutoff {
      snapshot.candidates.removeAll { $0.lastSeen < cutoff }
    }
    rescore(now: now)
    if snapshot.candidates.count > Self.maxCandidates {
      snapshot.candidates =
        snapshot.candidates
        .sorted { $0.score > $1.score }
        .prefix(Self.maxCandidates)
        .map { $0 }
    }
    pruneConfirmedToCap()
    persist()
  }

  /// Replaces the entire candidate index from a full recompute over the archive.
  /// Learned terms/denylist are preserved; injection only changes when recurring candidates cross
  /// the auto-vocabulary threshold.
  func replaceCandidates(_ extractedPerDoc: [[ExtractedTerm]], dates: [Date], now: Date = Date()) {
    var index: [String: MemoryCandidate] = [:]
    let denied = Set(snapshot.denylist.map { $0.lowercased() })

    for (offset, extracted) in extractedPerDoc.enumerated() {
      let date = offset < dates.count ? dates[offset] : now
      for term in extracted {
        let key = term.lemma.lowercased()
        guard !denied.contains(key) else { continue }
        if var existing = index[key] {
          existing.docFrequency += 1
          existing.lastSeen = max(existing.lastSeen, date)
          existing.surfaceForm = term.surfaceForm
          if term.category.injectionRank < existing.category.injectionRank {
            existing.category = term.category
          }
          index[key] = existing
        } else {
          index[key] = MemoryCandidate(
            lemma: term.lemma,
            surfaceForm: term.surfaceForm,
            category: term.category,
            docFrequency: 1,
            lastSeen: date
          )
        }
      }
    }

    snapshot.candidates = Array(index.values)
    rescore(now: now)
    autoConfirmRecurringCandidates()
    decayAndPrune(now: now)
  }

  // MARK: - Watermark

  func updateWatermark(contentHash: String, date: Date = Date()) {
    snapshot.lastProcessed = MemoryWatermark(contentHash: contentHash, date: date)
    persist()
  }

  /// True when the archive content hash already matches the last processed watermark.
  func isUpToDate(with contentHash: String) -> Bool {
    snapshot.lastProcessed?.contentHash == contentHash
  }

  // MARK: - Scoring

  /// Importance = recency-weighted document frequency. Rarity is already encoded upstream
  /// (only OOV / out-of-language / rare-noun tokens become candidates at all).
  private func rescore(now: Date) {
    for index in snapshot.candidates.indices {
      let candidate = snapshot.candidates[index]
      let ageDays = max(0, now.timeIntervalSince(candidate.lastSeen) / 86_400)
      // Half-life ~30 days: recent recurrence outweighs old one-offs.
      let recencyWeight = pow(0.5, ageDays / 30.0)
      let frequencyComponent = log(Double(candidate.docFrequency) + 1)
      snapshot.candidates[index].score = frequencyComponent * recencyWeight
    }
  }

  private func autoConfirmRecurringCandidates() {
    let denied = Set(snapshot.denylist.map { $0.lowercased() })
    let confirmedIDs = Set(snapshot.confirmed.map { $0.id })
    let confirmedLemmas = Set(snapshot.confirmed.compactMap { $0.lemma?.lowercased() })

    for candidate in snapshot.candidates {
      let lemmaKey = candidate.lemma.lowercased()
      let surfaceKey = candidate.surfaceForm.lowercased()
      guard !denied.contains(lemmaKey), !denied.contains(surfaceKey) else { continue }
      guard !confirmedIDs.contains(candidate.id), !confirmedLemmas.contains(lemmaKey) else {
        continue
      }
      guard Self.shouldAutoConfirm(candidate) else { continue }
      snapshot.confirmed.append(
        MemoryConfirmedTerm(
          term: candidate.surfaceForm,
          lemma: candidate.lemma,
          category: candidate.category
        )
      )
    }
    pruneConfirmedToCap()
  }

  /// Keeps only the top `maxConfirmed` learned terms (best-first by the injection ranking), so the
  /// auto-learned vocabulary stays a focused set instead of accumulating endlessly. Pure ordering;
  /// callers persist. Manual terms live in `AppSettings.customTerms` and are unaffected.
  private func pruneConfirmedToCap() {
    guard snapshot.confirmed.count > Self.maxConfirmed else { return }
    let candidatesByID = Dictionary(
      snapshot.candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    snapshot.confirmed =
      snapshot.confirmed
      .sorted { lhs, rhs in
        if lhs.category.injectionRank != rhs.category.injectionRank {
          return lhs.category.injectionRank < rhs.category.injectionRank
        }
        let lhsScore = candidatesByID[lhs.id]?.score ?? 0
        let rhsScore = candidatesByID[rhs.id]?.score ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.addedAt > rhs.addedAt
      }
      .prefix(Self.maxConfirmed)
      .map { $0 }
  }

  nonisolated static func shouldAutoConfirm(_ candidate: MemoryCandidate) -> Bool {
    let lemma = candidate.lemma.trimmingCharacters(in: .whitespacesAndNewlines)
    let surface = candidate.surfaceForm.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lemma.isEmpty, !surface.isEmpty else { return false }
    guard !commonTermDenylist.contains(MemoryCommonWords.normalized(lemma)),
      !commonTermDenylist.contains(MemoryCommonWords.normalized(surface))
    else {
      return false
    }

    switch candidate.category {
    case .name, .foreign:
      return candidate.docFrequency >= autoConfirmNameOrForeignDocFrequency
    case .term:
      return candidate.docFrequency >= autoConfirmTermDocFrequency
    }
  }

  // MARK: - Persistence

  private static func loadSnapshot(from url: URL, decoder: JSONDecoder) -> MemorySnapshot {
    guard let data = try? Data(contentsOf: url) else { return MemorySnapshot() }
    guard let decoded = try? decoder.decode(MemorySnapshot.self, from: data) else {
      memoryLogger.error("Failed to decode memory.json; starting empty.")
      return MemorySnapshot()
    }
    return decoded
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
      memoryLogger.error(
        "Failed to persist memory: \(error.localizedDescription, privacy: .public)")
    }
  }
}
