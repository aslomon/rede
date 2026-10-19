import Foundation
import os

/// OpenAI Chat Completions transport with one shared retry and per-attempt policy checks.
struct OpenAIRewriteProvider: RewriteProvider {
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let modelID: String
  let reasoningEffort: RewriteReasoningEffort?
  private let apiKeyProvider: @Sendable () -> String?
  private let isRemoteAllowed: @Sendable () -> Bool
  private let transport: Transport

  /// Nil uses the registry default: explicit none for Luna, API default for other models.
  init(
    modelID: String, reasoningEffort: RewriteReasoningEffort? = nil,
    isRemoteAllowed: @escaping @Sendable () -> Bool = { true }
  ) {
    self.init(modelID: modelID, reasoningEffort: reasoningEffort,
      apiKeyProvider: { KeychainService.load(key: .openAIAPIKey) },
      isRemoteAllowed: isRemoteAllowed, transport: { request in
        let session = Self.sessions[request.timeoutInterval] ?? Self.sessions[45]!
        return try await session.data(for: request)
      })
  }

  init(
    modelID: String, reasoningEffort: RewriteReasoningEffort? = nil, apiKey: String,
    isRemoteAllowed: @escaping @Sendable () -> Bool = { true }, transport: @escaping Transport
  ) {
    self.init(modelID: modelID, reasoningEffort: reasoningEffort, apiKeyProvider: { apiKey },
      isRemoteAllowed: isRemoteAllowed, transport: transport)
  }

  init(
    modelID: String, reasoningEffort: RewriteReasoningEffort? = nil,
    apiKeyProvider: @escaping @Sendable () -> String?,
    isRemoteAllowed: @escaping @Sendable () -> Bool = { true }, transport: @escaping Transport
  ) {
    self.modelID = modelID
    self.reasoningEffort = reasoningEffort
    self.apiKeyProvider = apiKeyProvider
    self.isRemoteAllowed = isRemoteAllowed
    self.transport = transport
  }

  private static let logger = Logger(subsystem: "app.rede.mac", category: "RewriteProvider")
  private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
  private static let sessions: [TimeInterval: URLSession] = {
    let efforts: [RewriteReasoningEffort?] = [nil, .medium, .high, .xhigh]
    return Dictionary(uniqueKeysWithValues: efforts.map { effort in
      (RewriteModelRegistry.requestTimeout(for: effort),
        URLSession(configuration: sessionConfiguration(for: effort)))
    })
  }()

  static func sessionConfiguration(for effort: RewriteReasoningEffort?) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.timeoutIntervalForRequest = RewriteModelRegistry.requestTimeout(for: effort)
    configuration.timeoutIntervalForResource = RewriteModelRegistry.resourceTimeout(for: effort)
    return configuration
  }

  private struct Attempt: Equatable {
    let model: String
    let effort: RewriteReasoningEffort?
  }

  private enum RetryableError: Error { case effortRejected(String) }

  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws -> RewriteOutcome {
    try validateReasoningEffort()
    let initial = Attempt(model: modelID,
      effort: RewriteModelRegistry.resolvedEffort(modelID: modelID, stored: reasoningEffort))
    do {
      return try await rewriteWithRetry(initial: initial, systemPrompt: systemPrompt,
        userText: userText, temperature: temperature)
    } catch RetryableError.effortRejected(let message) {
      throw LLMError.apiError(message)
    }
  }

  private func rewriteWithRetry(
    initial: Attempt, systemPrompt: String, userText: String, temperature: Double
  ) async throws -> RewriteOutcome {
    do {
      return try await outcome(for: initial, systemPrompt: systemPrompt,
        userText: userText, temperature: temperature)
    } catch {
      guard let retry = retryAttempt(after: error, initial: initial) else { throw error }
      let requestedEffort = initial.effort?.rawValue ?? "api_default"
      let usedEffort = retry.effort?.rawValue ?? "api_default"
      Self.logger.notice(
        """
        rewrite retry requested=\(initial.model, privacy: .public) used=\(retry.model, privacy: .public) \
        requested_effort=\(requestedEffort, privacy: .public) used_effort=\(usedEffort, privacy: .public)
        """
      )
      // Deliberately outside another catch: the two fallback types share one retry budget.
      return try await outcome(for: retry, systemPrompt: systemPrompt,
        userText: userText, temperature: temperature)
    }
  }

  private func retryAttempt(after error: Error, initial: Attempt) -> Attempt? {
    if case LLMError.modelUnavailable = error,
      initial.model != RewriteModelRegistry.safeFallbackModelID {
      return Attempt(model: RewriteModelRegistry.safeFallbackModelID, effort: nil)
    }
    if case RetryableError.effortRejected = error, initial.effort != nil {
      let defaultEffort = RewriteModelRegistry.resolvedEffort(modelID: initial.model, stored: nil)
      if defaultEffort != initial.effort { return Attempt(model: initial.model, effort: defaultEffort) }
    }
    return nil
  }

  private func validateReasoningEffort() throws {
    if let reasoningEffort,
      !RewriteModelRegistry.supportedEfforts(for: modelID).contains(reasoningEffort) {
      throw OpenAIRewriteConfigurationError.unsupportedReasoningEffort(
        modelID: modelID, effort: reasoningEffort)
    }
  }

  private func outcome(
    for attempt: Attempt, systemPrompt: String, userText: String, temperature: Double
  ) async throws -> RewriteOutcome {
    let text = try await send(attempt: attempt, systemPrompt: systemPrompt,
      userText: userText, temperature: temperature)
    return RewriteOutcome(text: text, usedModelID: attempt.model, requestedModelID: modelID)
  }

  private func send(
    attempt: Attempt, systemPrompt: String, userText: String, temperature: Double
  ) async throws -> String {
    let payload = OpenAIRewriteRequest(model: attempt.model, messages: [
      .init(role: "system", content: systemPrompt), .init(role: "user", content: userText)
    ], temperature: RewriteModelRegistry.supportsTemperature(attempt.model) ? temperature : nil,
      reasoningEffort: attempt.effort)
    let body = try JSONEncoder().encode(payload)
    try Task.checkCancellation()
    guard isRemoteAllowed() else { throw OpenAIRemotePolicyError.remoteNotAllowed }
    try Task.checkCancellation()
    guard let apiKey = apiKeyProvider() else { throw LLMError.notConfigured }
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = RewriteModelRegistry.requestTimeout(for: attempt.effort)
    request.httpBody = body
    let startedAt = Date()
    let (data, response) = try await transport(request)
    try Task.checkCancellation()
    return try Self.decodeContent(data: data, response: response, attempt: attempt,
      elapsedMilliseconds: Int((Date().timeIntervalSince(startedAt) * 1000).rounded()))
  }

  private static func decodeContent(
    data: Data, response: URLResponse, attempt: Attempt, elapsedMilliseconds: Int
  ) throws -> String {
    guard let http = response as? HTTPURLResponse else {
      throw LLMError.networkError("Keine gültige Antwort")
    }
    Self.logger.info(
      """
      stage=openai_rewrite model=\(attempt.model, privacy: .public) \
      status=\(http.statusCode, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public)
      """
    )
    guard http.statusCode == 200 else {
      try throwAPIError(data: data, status: http.statusCode, attempt: attempt)
    }
    let result = try JSONDecoder().decode(OpenAIRewriteResponse.self, from: data)
    guard let content = result.choices?.first?.message?.content,
      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.noContent }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func throwAPIError(data: Data, status: Int, attempt: Attempt) throws -> Never {
    let parsed = (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error
    if status == 404 || status == 400 && parsed?.isModelUnavailable == true
      || status == 403 && parsed?.code == "model_not_found" {
      throw LLMError.modelUnavailable(attempt.model)
    }
    let message = parsed?.message ?? "Status \(status)"
    if status == 400, attempt.effort != nil, parsed?.namesReasoningEffort == true {
      throw RetryableError.effortRejected(message)
    }
    throw LLMError.apiError(message)
  }
}
