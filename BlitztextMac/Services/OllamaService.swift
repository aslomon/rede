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

  /// Default model id pre-selected for new installs (friendly, broadly available).
  static let defaultModelName = "gemma3"

  /// Curated picker defaults. `gemma3:12b` maps to the 8-bit Gemma quality target;
  /// `gemma3` stays the friendly default for smaller machines.
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
}
