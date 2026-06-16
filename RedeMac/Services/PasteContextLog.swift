import Foundation
import OSLog
import Observation

private let contextLogger = Logger(subsystem: "app.rede.mac", category: "ContextLog")

// MARK: - Category

/// Where a dictation landed, coarsely classified from the target app + focused element role.
/// Drives the on-device "Office Memory" overview ("Du diktierst meist in: Mail …"). Privacy-local.
enum PasteContextCategory: String, Codable, CaseIterable, Sendable {
  case email
  case chat
  case code
  case browser
  case notes
  case document
  case terminal
  case other

  /// German label for the overview chips/badges (du-form, knapp).
  var displayName: String {
    switch self {
    case .email: return "Mail"
    case .chat: return "Chat"
    case .code: return "Code"
    case .browser: return "Browser"
    case .notes: return "Notizen"
    case .document: return "Dokument"
    case .terminal: return "Terminal"
    case .other: return "Sonstiges"
    }
  }

  /// SF Symbol for the chip/badge icon.
  var symbolName: String {
    switch self {
    case .email: return "envelope.fill"
    case .chat: return "bubble.left.and.bubble.right.fill"
    case .code: return "chevron.left.forwardslash.chevron.right"
    case .browser: return "safari.fill"
    case .notes: return "note.text"
    case .document: return "doc.fill"
    case .terminal: return "terminal.fill"
    case .other: return "app.dashed"
    }
  }
}

// MARK: - Context entry

/// A single recorded "where did I dictate" event. Text-free by design — only metadata about the
/// target app + window/element, never the dictated content. Logged alongside the opt-in archive.
struct PasteContext: Codable, Identifiable, Sendable {
  let id: UUID
  let date: Date
  let appBundleID: String?
  let appName: String?
  let windowTitle: String?
  let elementRole: String?
  let category: PasteContextCategory
  let mode: WorkflowType
  let charCount: Int

  init(
    id: UUID = UUID(),
    date: Date,
    appBundleID: String?,
    appName: String?,
    windowTitle: String?,
    elementRole: String?,
    category: PasteContextCategory,
    mode: WorkflowType,
    charCount: Int
  ) {
    self.id = id
    self.date = date
    self.appBundleID = appBundleID
    self.appName = appName
    self.windowTitle = windowTitle
    self.elementRole = elementRole
    self.category = category
    self.mode = mode
    self.charCount = charCount
  }
}

// MARK: - Categorizer (pure, testable)

extension PasteContextCategory {
  /// Maps a target app bundle id (+ optional focused-element role) to a coarse category.
  /// Pure + side-effect-free so it can be unit-tested without any AppKit/AX state.
  /// Matching is substring + case-insensitive on the bundle id so vendor variants
  /// (Stable/Insiders/EAP suffixes) are caught without an exhaustive list.
  static func categorize(
    bundleID: String?, role: String?, windowTitle: String? = nil
  ) -> PasteContextCategory {
    let id = (bundleID ?? "").lowercased()
    let normalizedRole = (role ?? "").lowercased()

    if let byBundle = categoryFromBundle(id) {
      // A browser hosts most web apps, so a Gmail/Outlook/Notion/Linear tab should read as the
      // underlying app, not a generic "Browser". Refine from the window title when it names one.
      if byBundle == .browser, let webApp = webAppCategory(fromTitle: windowTitle) {
        return webApp
      }
      return byBundle
    }

    // No bundle match: fall back to role hints (e.g. a terminal text element).
    if normalizedRole.contains("terminal") { return .terminal }
    return .other
  }

  /// Refines a browser destination from its window title when it clearly names a known web app
  /// (e.g. "Inbox (3) - you@gmail.com - Gmail"). Returns nil when nothing matches → stays .browser.
  private static func webAppCategory(fromTitle title: String?) -> PasteContextCategory? {
    let normalized = (title ?? "").lowercased()
    guard !normalized.isEmpty else { return nil }
    if matches(normalized, emailWebFragments) { return .email }
    if matches(normalized, chatWebFragments) { return .chat }
    if matches(normalized, codeWebFragments) { return .code }
    if matches(normalized, docWebFragments) { return .document }
    if matches(normalized, notesWebFragments) { return .notes }
    return nil
  }

  private static func categoryFromBundle(_ id: String) -> PasteContextCategory? {
    guard !id.isEmpty else { return nil }
    if matches(id, emailBundleFragments) { return .email }
    if matches(id, chatBundleFragments) { return .chat }
    if matches(id, codeBundleFragments) { return .code }
    if matches(id, browserBundleFragments) { return .browser }
    if matches(id, notesBundleFragments) { return .notes }
    if matches(id, documentBundleFragments) { return .document }
    if matches(id, terminalBundleFragments) { return .terminal }
    return nil
  }

  private static func matches(_ id: String, _ fragments: [String]) -> Bool {
    fragments.contains { id.contains($0) }
  }

  // Reasonable, not exhaustive, lowercase bundle-id fragments.
  private static let emailBundleFragments = [
    "com.apple.mail", "spark", "readdle.smartemail", "airmail", "com.google.gmail",
    "com.microsoft.outlook", "mimestream",
  ]
  private static let chatBundleFragments = [
    "slack", "whatsapp", "messages", "mobilesms", "ichat", "messenger", "telegram", "discord",
    "signal",
  ]
  private static let codeBundleFragments = [
    "com.microsoft.vscode", "com.apple.dt.xcode", "sublimetext", "jetbrains", "com.github.atom",
    "zed", "nova",
  ]
  private static let browserBundleFragments = [
    "com.apple.safari", "google.chrome", "chromium", "company.thebrowser.browser", "arc",
    "firefox", "com.brave", "com.microsoft.edgemac", "opera",
  ]
  private static let notesBundleFragments = [
    "com.apple.notes", "notion", "obsidian", "bear", "craft", "roam",
  ]
  private static let documentBundleFragments = [
    "com.apple.iwork.pages", "com.microsoft.word", "google.docs", "com.apple.textedit",
    "libreoffice", "openoffice",
  ]
  private static let terminalBundleFragments = [
    "com.apple.terminal", "iterm", "com.googlecode.iterm2", "warp", "hyper", "alacritty",
    "kitty", "wezterm",
  ]

  // Window-title fragments for web apps hosted in a browser. Lowercase; matched only when the
  // bundle already resolved to .browser, so a desktop app's bundle id always wins over these.
  private static let emailWebFragments = ["gmail", "outlook", "proton mail", "fastmail"]
  private static let chatWebFragments = [
    "slack", "discord", "whatsapp", "telegram", "microsoft teams", "google chat",
  ]
  private static let codeWebFragments = [
    "github", "gitlab", "codepen", "codesandbox", "stackblitz",
  ]
  private static let docWebFragments = ["google docs", "google sheets", "google slides"]
  private static let notesWebFragments = ["notion", "linear", "confluence", "coda.io"]
}

// MARK: - Store

/// Bounded, on-device log of dictation destinations. Mirrors `ArchiveStore`: own JSON file via
/// `AppSupportPaths`, written 0600, capped to the most recent entries. Opt-in (wired only while
/// the archive is enabled), so disabled == zero I/O. Holds no dictated text — only metadata.
@Observable
@MainActor
final class ContextLogStore {
  nonisolated static let maxEntries = 300
  /// Auto-expiry for this metadata-only log (window titles can still leak doc names / subjects),
  /// matching the 90-day archive so a destination never lingers indefinitely past its usefulness.
  nonisolated static let retentionDays = 90

  /// Newest entries first.
  private(set) var contexts: [PasteContext] = []

  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileURL: URL = AppSupportPaths.contextLogURL) {
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

  /// Appends a context entry, prunes by age + count, then persists. Newest-first.
  func append(_ context: PasteContext) {
    contexts.insert(context, at: 0)
    prune()
    persist()
  }

  /// Removes everything and deletes the backing file ("Verlauf löschen").
  func clear() {
    contexts = []
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Prunes age-expired entries NOW (not just on append/load), for the long-lived menu-bar process.
  /// Persists only if something dropped.
  func pruneExpired() {
    let before = contexts.count
    prune()
    if contexts.count != before { persist() }
  }

  /// Category counts across all logged contexts, descending by count (ties: category order).
  func topCategories() -> [(PasteContextCategory, Int)] {
    var counts: [PasteContextCategory: Int] = [:]
    for context in contexts {
      counts[context.category, default: 0] += 1
    }
    return
      counts
      .sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key.rawValue < rhs.key.rawValue
      }
      .map { ($0.key, $0.value) }
  }

  // MARK: - Persistence

  /// Drops contexts older than `retentionDays`, then caps to the most recent `maxEntries`.
  private func prune() {
    if let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) {
      contexts.removeAll { $0.date < cutoff }
    }
    if contexts.count > Self.maxEntries {
      contexts = Array(contexts.prefix(Self.maxEntries))
    }
  }

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    guard let decoded = try? decoder.decode([PasteContext].self, from: data) else {
      contextLogger.error("Failed to decode context log; ignoring.")
      return
    }
    contexts = decoded.sorted { $0.date > $1.date }
    prune()
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try encoder.encode(contexts)
      try SecureFileWriter.write(data, to: fileURL)
    } catch {
      contextLogger.error(
        "Failed to persist context log: \(error.localizedDescription, privacy: .public)")
    }
  }
}
