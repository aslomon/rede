import Foundation

/// Lightweight client for the local Ollama server (https://ollama.com).
/// Used by the settings UI to show a reachability status and the list of installed models,
/// plus a curated default list for the model picker. No SPM dependency — plain `URLSession`.
/// All traffic targets `localhost` only; nothing leaves the machine.
enum OllamaService {
  /// Default local Ollama base URL.
  static let baseURLString = "http://localhost:11434"

  /// User-facing label for the local backend.
  static let backendLabel = "Lokal (Ollama)"

  /// No model is pre-selected for new installs. Pre-selecting a curated name (e.g. "gemma3")
  /// would falsely imply readiness before the user has actually pulled anything, so a fresh
  /// install starts in the honest "Kein lokales Modell" state. An empty string is the sentinel
  /// for "nothing selected" and is treated as not-configured everywhere downstream.
  static let defaultModelName = ""

  /// Friendly suggestion surfaced in copy/hints (`ollama pull <name>`). NOT auto-selected.
  static let suggestedModelName = "gemma3"

  /// Curated picker suggestions. These are real Ollama tags (verified against the Ollama library):
  /// `gemma3`/`gemma3:12b` (Gemma 3), `qwen3`/`qwen3:8b` (Qwen 3), `llama3.2` (Llama 3.2). They are
  /// only shown as "nicht geladen" suggestions — never as installed unless `/api/tags` confirms it.
  static let curatedModelNames = [
    "gemma3",
    "gemma3:12b",
    "qwen3",
    "qwen3:8b",
    "llama3.2",
  ]

  private static let tagsURL = URL(string: "\(baseURLString)/api/tags")!

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    // Short budget: this only gates a status line / picker, never the actual rewrite.
    configuration.timeoutIntervalForRequest = 2
    configuration.timeoutIntervalForResource = 2
    return URLSession(configuration: configuration)
  }()

  private struct TagsResponse: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]?
  }

  /// True when the local Ollama server answers `GET /api/tags`. Never throws — a down server
  /// (connection refused / timeout) simply returns `false`.
  static func statusCheck() async -> Bool {
    do {
      let (_, response) = try await session.data(from: tagsURL)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }

  /// Names of the models currently pulled into the local Ollama install (e.g. "gemma3:latest").
  /// Returns an empty array when the server is unreachable or has no models.
  static func installedModels() async -> [String] {
    do {
      let (data, response) = try await session.data(from: tagsURL)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
      let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
      return decoded.models?.map(\.name) ?? []
    } catch {
      return []
    }
  }

  /// Curated defaults unioned with any installed models, de-duplicated, preserving curated order
  /// first. Used to populate the picker so a model the user already pulled is always selectable.
  static func pickerModelNames(installed: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for name in curatedModelNames + installed {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
      seen.insert(trimmed)
      result.append(trimmed)
    }
    return result
  }

  /// One selectable picker entry plus its honest pulled/not-pulled state. Installed models are
  /// listed first (so the user's real models are most prominent), curated suggestions follow.
  struct PickerModel: Identifiable, Hashable {
    let name: String
    let isInstalled: Bool

    var id: String { name }

    /// Picker-ready label. Installed reads "name · geladen"; a curated-but-missing model reads
    /// "name · nicht geladen" so it can never be mistaken for something ready to run.
    var menuLabel: String {
      isInstalled ? "\(name) · geladen" : "\(name) · nicht geladen"
    }
  }

  /// True when `candidate` matches one of the actually-pulled `installed` tags. Ollama reports
  /// fully-qualified tags (e.g. "gemma3:latest"); a curated bare name like "gemma3" must match
  /// "gemma3:latest", while an explicit tag like "gemma3:12b" must match exactly.
  static func isInstalled(_ candidate: String, in installed: [String]) -> Bool {
    let target = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty else { return false }
    let normalizedTarget = target.contains(":") ? target : "\(target):latest"
    return installed.contains { rawInstalled in
      let name = rawInstalled.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedInstalled = name.contains(":") ? name : "\(name):latest"
      return normalizedInstalled == normalizedTarget || name == target
    }
  }

  /// Ordered picker rows: actually-installed models first (each flagged installed), then curated
  /// suggestions that are NOT yet pulled (flagged not-installed). De-duplicated across both.
  static func pickerModels(installed: [String]) -> [PickerModel] {
    var seen = Set<String>()
    var result: [PickerModel] = []

    func add(_ name: String, isInstalled: Bool) {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
      result.append(PickerModel(name: trimmed, isInstalled: isInstalled))
    }

    for name in installed { add(name, isInstalled: true) }
    for name in curatedModelNames where !isInstalled(name, in: installed) {
      add(name, isInstalled: false)
    }
    return result
  }
}
