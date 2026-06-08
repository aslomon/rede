import Foundation

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

    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
  }

  private struct ChatResponse: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        let content: String?
      }
      let message: Message?
    }
    let choices: [Choice]?
  }

  private struct ErrorResponse: Decodable {
    struct APIError: Decodable {
      let message: String?
    }
    let error: APIError?
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

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch let urlError as URLError {
      switch urlError.code {
      case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .timedOut,
        .networkConnectionLost, .dnsLookupFailed:
        throw LLMError.localModelUnavailable(
          "llama.cpp ist lokal nicht erreichbar. Starte Blitztext neu oder prüfe das lokale Modell."
        )
      default:
        throw LLMError.networkError(urlError.localizedDescription)
      }
    }

    guard let http = response as? HTTPURLResponse else {
      throw LLMError.networkError("Keine gültige Antwort")
    }
    guard http.statusCode == 200 else {
      if http.statusCode == 404 {
        throw LLMError.localModelUnavailable("Das lokale llama.cpp-Modell ist nicht verfügbar.")
      }
      if http.statusCode == 503 {
        throw LLMError.localModelUnavailable("llama.cpp lädt das Modell noch. Bitte kurz warten.")
      }
      throw LLMError.apiError(Self.errorMessage(from: data) ?? "Status \(http.statusCode)")
    }
    return try Self.decodeChatContent(data)
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
      temperature: temperature
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 120
    request.httpBody = try JSONEncoder().encode(payload)
    return request
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

  private static func errorMessage(from data: Data) -> String? {
    (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message
  }
}
