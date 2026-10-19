import Foundation

private struct OpenAIModelsResponse: Decodable {
  struct Model: Decodable { let id: String }
  let data: [Model]?
}

extension RewriteModelRegistry {
  typealias ModelListingTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  private static let modelListingSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
  }()

  static func fetchAvailableChatModels(
    isRemoteAllowed: @escaping @Sendable () -> Bool = { true }
  ) async throws -> [String] {
    return try await fetchAvailableChatModels(
      apiKeyProvider: { KeychainService.load(key: .openAIAPIKey) }, isRemoteAllowed: isRemoteAllowed,
      transport: { request in try await modelListingSession.data(for: request) })
  }

  static func fetchAvailableChatModels(
    apiKey: String, isRemoteAllowed: @escaping @Sendable () -> Bool = { true },
    transport: @escaping ModelListingTransport
  ) async throws -> [String] {
    try await fetchAvailableChatModels(apiKeyProvider: { apiKey },
      isRemoteAllowed: isRemoteAllowed, transport: transport)
  }

  static func fetchAvailableChatModels(
    apiKeyProvider: @Sendable () -> String?, isRemoteAllowed: @Sendable () -> Bool,
    transport: ModelListingTransport
  ) async throws -> [String] {
    try Task.checkCancellation()
    guard isRemoteAllowed() else { throw OpenAIRemotePolicyError.remoteNotAllowed }
    try Task.checkCancellation()
    guard let apiKey = apiKeyProvider() else { throw LLMError.notConfigured }
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
    request.httpMethod = "GET"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30
    let (data, response) = try await transport(request)
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw LLMError.apiError("Modell-Liste konnte nicht geladen werden.")
    }
    let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
    return Array(Set((decoded.data ?? []).map(\.id).filter(isChatModel))).sorted()
  }

  private static func isChatModel(_ modelID: String) -> Bool {
    let lowered = modelID.lowercased()
    let prefixes = ["gpt-", "o1", "o3", "o4", "chatgpt"]
    let excluded = ["audio", "realtime", "transcribe", "tts", "image", "embedding",
      "search", "moderation"]
    return prefixes.contains { lowered.hasPrefix($0) }
      && !excluded.contains { lowered.contains($0) }
  }
}
