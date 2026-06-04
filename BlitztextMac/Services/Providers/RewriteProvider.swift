import Foundation
import FoundationModels

// MARK: - Selection context (Phase 2)

/// Text the user had selected / surrounding the cursor in the frontmost app,
/// captured at recording start. In-memory only — never persisted.
struct SelectionContext {
  var selectedText: String
  var surroundingText: String
  var appBundleID: String?

  var isEmpty: Bool {
    selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && surroundingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

// MARK: - Provider seam

/// Abstracts the rewrite transport so a mode can run on OpenAI or on-device.
/// Prompt-building stays in `LLMService`; a provider only turns
/// (systemPrompt, userText) into rewritten text.
protocol RewriteProvider: Sendable {
  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws -> String
}

// MARK: - Fail-closed provider

/// Used when an offline backend is required but unavailable (e.g. macOS < 26).
/// Never falls back to the network — guarantees the offline invariant.
struct UnavailableRewriteProvider: RewriteProvider {
  let message: String

  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws -> String {
    throw LLMError.localModelUnavailable(message)
  }
}

// MARK: - OpenAI provider

/// OpenAI Chat Completions transport. Owns the HTTP that used to live in LLMService.
struct OpenAIRewriteProvider: RewriteProvider {
  let modelID: String

  private static let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 45
    configuration.timeoutIntervalForResource = 45
    return URLSession(configuration: configuration)
  }()

  private struct ChatRequest: Encodable {
    struct Message: Encodable {
      let role: String
      let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
      case model, messages, temperature
    }

    func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(model, forKey: .model)
      try c.encode(messages, forKey: .messages)
      // Omit entirely (not null) when unsupported — GPT-5.x reject the key.
      try c.encodeIfPresent(temperature, forKey: .temperature)
    }
  }

  private struct ChatResponse: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable { let content: String? }
      let message: Message?
    }
    let choices: [Choice]?
  }

  private struct ErrorResponse: Decodable {
    struct APIError: Decodable {
      let message: String?
      let code: String?
    }
    let error: APIError?
  }

  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws -> String {
    do {
      return try await send(
        systemPrompt: systemPrompt, userText: userText, model: modelID, temperature: temperature)
    } catch let LLMError.modelUnavailable(model)
      where model != RewriteModelRegistry.safeFallbackModelID
    {
      // Chosen model not available on this account → retry once with a safe model.
      return try await send(
        systemPrompt: systemPrompt,
        userText: userText,
        model: RewriteModelRegistry.safeFallbackModelID,
        temperature: temperature
      )
    }
  }

  private func send(systemPrompt: String, userText: String, model: String, temperature: Double)
    async throws -> String
  {
    guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
      throw LLMError.notConfigured
    }

    let payload = ChatRequest(
      model: model,
      messages: [
        .init(role: "system", content: systemPrompt),
        .init(role: "user", content: userText),
      ],
      temperature: RewriteModelRegistry.supportsTemperature(model) ? temperature : nil
    )

    var request = URLRequest(url: Self.chatCompletionsURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 45
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await Self.session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMError.networkError("Keine gültige Antwort")
    }

    guard httpResponse.statusCode == 200 else {
      let parsed = Self.errorPayload(from: data)
      // Model-not-found / unsupported → surface as modelUnavailable so we can fall back.
      if httpResponse.statusCode == 404
        || httpResponse.statusCode == 400
          && (parsed?.code == "model_not_found"
            || (parsed?.message?.lowercased().contains("model") ?? false)
              && (parsed?.message?.lowercased().contains("does not exist") ?? false))
      {
        throw LLMError.modelUnavailable(model)
      }
      throw LLMError.apiError(parsed?.message ?? "Status \(httpResponse.statusCode)")
    }

    let result = try JSONDecoder().decode(ChatResponse.self, from: data)
    guard let content = result.choices?.first?.message?.content,
      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw LLMError.noContent
    }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func errorPayload(from data: Data) -> ErrorResponse.APIError? {
    (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
  }
}

// MARK: - Ollama provider (local, offline via a local HTTP server)

/// Local rewrite transport backed by Ollama (https://ollama.com), a local model server.
/// Talks to its OpenAI-compatible endpoint over `URLSession` — no SPM dependency, no streaming.
/// The text never leaves the machine: the request targets `localhost` only.
struct OllamaRewriteProvider: RewriteProvider {
  let modelID: String

  private static let chatCompletionsURL = URL(
    string: "\(OllamaService.baseURLString)/v1/chat/completions")!

  private static let unreachableHint =
    "Ollama ist nicht erreichbar. Installiere Ollama (ollama.com), starte es und lade ein Modell, "
    + "z. B. `ollama pull gemma3`."

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    // Local generation can take a while on a cold model load — keep a generous budget.
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 120
    return URLSession(configuration: configuration)
  }()

  private struct ChatRequest: Encodable {
    struct Message: Encodable {
      let role: String
      let content: String
    }
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
  }

  private struct ChatResponse: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable { let content: String? }
      let message: Message?
    }
    let choices: [Choice]?
  }

  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws -> String {
    let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedModelID.isEmpty else {
      throw LLMError.localModelUnavailable(
        "Kein lokales Sprachmodell ausgewählt. Lade eines mit `ollama pull gemma3` und wähle es in "
          + "den Einstellungen unter „Lokales Sprachmodell (Ollama)“ aus."
      )
    }

    let payload = ChatRequest(
      model: trimmedModelID,
      messages: [
        .init(role: "system", content: systemPrompt),
        .init(role: "user", content: userText),
      ],
      stream: false,
      temperature: temperature
    )

    var request = URLRequest(url: Self.chatCompletionsURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 120
    request.httpBody = try JSONEncoder().encode(payload)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await Self.session.data(for: request)
    } catch let urlError as URLError {
      switch urlError.code {
      case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .timedOut,
        .networkConnectionLost, .dnsLookupFailed:
        throw LLMError.localModelUnavailable(Self.unreachableHint)
      default:
        throw LLMError.networkError(urlError.localizedDescription)
      }
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMError.networkError("Keine gültige Antwort")
    }

    guard httpResponse.statusCode == 200 else {
      // A 404 here usually means the chosen model is not pulled yet.
      if httpResponse.statusCode == 404 {
        throw LLMError.localModelUnavailable(
          "Das lokale Modell „\(trimmedModelID)“ ist nicht installiert. Lade es mit `ollama pull \(trimmedModelID)`."
        )
      }
      let body = String(data: data, encoding: .utf8) ?? "Status \(httpResponse.statusCode)"
      throw LLMError.apiError(body)
    }

    let result = try JSONDecoder().decode(ChatResponse.self, from: data)
    guard
      let content = result.choices?.first?.message?.content?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !content.isEmpty
    else {
      throw LLMError.noContent
    }
    return content
  }
}

// MARK: - Apple Foundation Models provider (on-device, offline)

@available(macOS 26.0, *)
struct FoundationModelsRewriteProvider: RewriteProvider {
  /// Whether the on-device model can be used right now (local model on, eligible device, model ready).
  static func readiness() -> Result<Void, LLMError> {
    switch SystemLanguageModel.default.availability {
    case .available:
      return .success(())
    case .unavailable(.appleIntelligenceNotEnabled):
      return .failure(
        .localModelUnavailable(
          "Das lokale Modell ist nicht aktiviert. Aktiviere es in den Systemeinstellungen."))
    case .unavailable(.deviceNotEligible):
      return .failure(.localModelUnavailable("Dieses Gerät unterstützt das lokale Modell nicht."))
    case .unavailable(.modelNotReady):
      return .failure(
        .localModelUnavailable(
          "Das lokale Modell wird noch geladen. Bitte später erneut versuchen."))
    case .unavailable:
      return .failure(.localModelUnavailable("Das lokale Modell ist gerade nicht verfügbar."))
    }
  }

  static var isReady: Bool {
    if case .success = readiness() { return true }
    return false
  }

  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws -> String {
    if case .failure(let error) = Self.readiness() {
      throw error
    }
    let session = LanguageModelSession(instructions: systemPrompt)
    let options = GenerationOptions(temperature: temperature)
    let response = try await session.respond(to: userText, options: options)
    let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { throw LLMError.noContent }
    return content
  }
}
