import Foundation
import OSLog

private let llamaClientLogger = Logger(subsystem: "app.rede.mac", category: "LlamaCppClient")

private func llamaClientMilliseconds(since start: Date, until end: Date = Date()) -> Int {
  Int((end.timeIntervalSince(start) * 1000).rounded())
}

struct LlamaCppServerClient: Sendable {
  enum HealthStatus: Equatable, Sendable {
    case ready
    case loading
    case unavailable
  }

  private struct HealthPayload: Decodable {
    let status: String?
  }

  private struct ChatRequest: Encodable {
    struct Message: Encodable {
      let role: String
      let content: String
    }

    struct ChatTemplateOptions: Encodable {
      let enableThinking: Bool

      enum CodingKeys: String, CodingKey {
        case enableThinking = "enable_thinking"
      }
    }

    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int
    let chatTemplateOptions: ChatTemplateOptions

    enum CodingKeys: String, CodingKey {
      case model, messages, stream, temperature
      case maxTokens = "max_tokens"
      case chatTemplateOptions = "chat_template_kwargs"
    }
  }

  private struct ChatResponse: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        let content: String?
      }
      let message: Message?
    }
    let choices: [Choice]?
    let timings: ChatTimings?
  }

  struct ChatTimings: Decodable, Equatable, Sendable {
    let cacheN: Int?
    let promptN: Int?
    let promptMs: Double?
    let predictedN: Int?
    let predictedMs: Double?

    enum CodingKeys: String, CodingKey {
      case cacheN = "cache_n"
      case promptN = "prompt_n"
      case promptMs = "prompt_ms"
      case predictedN = "predicted_n"
      case predictedMs = "predicted_ms"
    }
  }

  private struct ErrorResponse: Decodable {
    struct APIError: Decodable {
      let message: String?
    }
    let error: APIError?
  }

  private struct EmbeddingRequest: Encodable {
    let model: String
    let input: String
  }

  private struct EmbeddingResponse: Decodable {
    struct Entry: Decodable {
      let embedding: [Double]
    }
    let data: [Entry]
  }

  let baseURL: URL
  let apiKey: String
  let session: URLSession

  init(
    baseURL: URL,
    apiKey: String,
    session: URLSession = {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.waitsForConnectivity = false
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.timeoutIntervalForRequest = 120
      configuration.timeoutIntervalForResource = 120
      return URLSession(configuration: configuration)
    }()
  ) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.session = session
  }

  func healthStatus() async -> HealthStatus {
    let url = baseURL.appendingPathComponent("health")
    do {
      let (data, response) = try await session.data(from: url)
      guard let http = response as? HTTPURLResponse else { return .unavailable }
      return try Self.healthStatus(statusCode: http.statusCode, data: data)
    } catch {
      return .unavailable
    }
  }

  static func healthStatus(statusCode: Int, data: Data) throws -> HealthStatus {
    if statusCode == 200 { return .ready }
    if statusCode == 503 { return .loading }
    if let payload = try? JSONDecoder().decode(HealthPayload.self, from: data),
      payload.status?.lowercased().contains("loading") == true
    {
      return .loading
    }
    return .unavailable
  }

  func chatCompletion(
    modelID: String,
    systemPrompt: String,
    userText: String,
    temperature: Double
  ) async throws -> String {
    let request = try makeChatRequest(
      modelID: modelID,
      systemPrompt: systemPrompt,
      userText: userText,
      temperature: temperature
    )

    let startedAt = Date()
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch let urlError as URLError {
      switch urlError.code {
      case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .timedOut,
        .networkConnectionLost, .dnsLookupFailed:
        throw LLMError.localModelUnavailable(
          "llama.cpp ist lokal nicht erreichbar. Starte rede neu oder prüfe das lokale Modell."
        )
      default:
        throw LLMError.networkError(urlError.localizedDescription)
      }
    }

    guard let http = response as? HTTPURLResponse else {
      throw LLMError.networkError("Keine gültige Antwort")
    }
    let responseElapsed = llamaClientMilliseconds(since: startedAt)
    guard http.statusCode == 200 else {
      Self.logChatCompletion(totalMilliseconds: responseElapsed, timings: nil)
      if http.statusCode == 404 {
        throw LLMError.localModelUnavailable("Das lokale llama.cpp-Modell ist nicht verfügbar.")
      }
      if http.statusCode == 503 {
        throw LLMError.localModelUnavailable("llama.cpp lädt das Modell noch. Bitte kurz warten.")
      }
      throw LLMError.apiError(Self.errorMessage(from: data) ?? "Status \(http.statusCode)")
    }
    let content = try Self.decodeChatContent(data)
    Self.logChatCompletion(
      totalMilliseconds: responseElapsed,
      timings: Self.decodeChatTimings(data)
    )
    return content
  }

  func makeChatRequest(
    modelID: String,
    systemPrompt: String,
    userText: String,
    temperature: Double
  ) throws -> URLRequest {
    let url = baseURL.appendingPathComponent("v1/chat/completions")
    let payload = ChatRequest(
      model: modelID,
      messages: [
        .init(role: "system", content: systemPrompt),
        .init(role: "user", content: userText),
      ],
      stream: false,
      temperature: temperature,
      maxTokens: Self.maxCompletionTokens(for: userText),
      chatTemplateOptions: .init(enableThinking: false)
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 120
    request.httpBody = try JSONEncoder().encode(payload)
    return request
  }

  static func maxCompletionTokens(for userText: String) -> Int {
    let trimmedCount = userText.trimmingCharacters(in: .whitespacesAndNewlines).count
    return min(2_048, max(384, trimmedCount / 2))
  }

  static func decodeChatContent(_ data: Data) throws -> String {
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

  static func decodeChatTimings(_ data: Data) -> ChatTimings? {
    (try? JSONDecoder().decode(ChatResponse.self, from: data))?.timings
  }

  /// Requests an embedding vector via the OpenAI-compatible `/v1/embeddings` endpoint.
  func embed(modelID: String, text: String) async throws -> [Double] {
    let url = baseURL.appendingPathComponent("v1/embeddings")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 120
    request.httpBody = try JSONEncoder().encode(EmbeddingRequest(model: modelID, input: text))

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch let urlError as URLError {
      switch urlError.code {
      case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .timedOut,
        .networkConnectionLost, .dnsLookupFailed:
        throw LLMError.localModelUnavailable("llama.cpp ist lokal nicht erreichbar (Embedding).")
      default:
        throw LLMError.networkError(urlError.localizedDescription)
      }
    }

    guard let http = response as? HTTPURLResponse else {
      throw LLMError.networkError("Keine gültige Antwort")
    }
    guard http.statusCode == 200 else {
      if http.statusCode == 503 {
        throw LLMError.localModelUnavailable("llama.cpp lädt das Embedding-Modell noch.")
      }
      throw LLMError.apiError(Self.errorMessage(from: data) ?? "Status \(http.statusCode)")
    }
    return try Self.decodeEmbedding(data)
  }

  static func decodeEmbedding(_ data: Data) throws -> [Double] {
    let result = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
    guard let vector = result.data.first?.embedding, !vector.isEmpty else {
      throw LLMError.noContent
    }
    return vector
  }

  private static func errorMessage(from data: Data) -> String? {
    (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message
  }

  private static func logChatCompletion(totalMilliseconds: Int, timings: ChatTimings?) {
    llamaClientLogger.info(
      "stage=chat_completion total_ms=\(totalMilliseconds, privacy: .public) cache_n=\(timings?.cacheN ?? -1, privacy: .public) prompt_n=\(timings?.promptN ?? -1, privacy: .public) prompt_ms=\(timings?.promptMs ?? -1, privacy: .public) predicted_n=\(timings?.predictedN ?? -1, privacy: .public) predicted_ms=\(timings?.predictedMs ?? -1, privacy: .public) stream=false ttft_ms=unavailable"
    )
  }
}
