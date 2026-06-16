import Foundation
import os

// MARK: - Rewrite outcome

/// Result of a single rewrite call. Carries the produced `text` plus the model that was REQUESTED
/// and the model that ACTUALLY ran. They differ only when the OpenAI provider fell back after the
/// chosen model was rejected — that gap is what the UI surfaces so a silent quality drop is visible.
struct RewriteOutcome: Equatable, Sendable {
  let text: String
  let variants: [String]
  /// The model that actually produced `text`. `nil` only when the provider can't name one.
  let usedModelID: String?
  /// The model the caller asked for. `nil` only when the provider can't name one.
  let requestedModelID: String?

  init(
    text: String,
    variants: [String]? = nil,
    usedModelID: String?,
    requestedModelID: String?
  ) {
    self.text = text
    self.variants = variants ?? [text]
    self.usedModelID = usedModelID
    self.requestedModelID = requestedModelID
  }

  /// True when the effective model differs from the requested one (a fallback happened).
  var didFallBack: Bool {
    guard let usedModelID, let requestedModelID else { return false }
    return usedModelID != requestedModelID
  }
}

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

// MARK: - Automatic rewrite context

/// Text from the focused input field, captured at recording start when the mode opts in.
/// In-memory only — never persisted. The text is capped before construction.
struct AutomaticRewriteContext: Sendable {
  var text: String
  var appBundleID: String?
  var appName: String?
  var windowTitle: String?

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

// MARK: - User identity context

/// Stable local identity of the person using rede. In-memory prompt context only; persisted in
/// `AppSettings.userDisplayName` so E-Mail/Prompt modes know from whose perspective they write.
struct UserIdentityContext: Sendable, Equatable {
  var displayName: String

  var isEmpty: Bool {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

// MARK: - Provider seam

/// Abstracts the rewrite transport so a mode can run on OpenAI or on-device.
/// Prompt-building stays in `LLMService`; a provider only turns
/// (systemPrompt, userText) into rewritten text.
protocol RewriteProvider: Sendable {
  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws
    -> RewriteOutcome
}

// MARK: - OpenAI provider

/// OpenAI Chat Completions transport. Owns the HTTP that used to live in LLMService.
struct OpenAIRewriteProvider: RewriteProvider {
  let modelID: String

  private static let logger = Logger(subsystem: "app.rede.mac", category: "RewriteProvider")

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

  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws
    -> RewriteOutcome
  {
    do {
      let text = try await send(
        systemPrompt: systemPrompt, userText: userText, model: modelID, temperature: temperature)
      return RewriteOutcome(text: text, usedModelID: modelID, requestedModelID: modelID)
    } catch let LLMError.modelUnavailable(model)
      where model != RewriteModelRegistry.safeFallbackModelID
    {
      // Chosen model not available on this account → retry once with a safe model. The used model
      // now differs from the requested one; surface that so the user notices the quality drop.
      let fallbackModel = RewriteModelRegistry.safeFallbackModelID
      Self.logger.notice(
        "requested \(model, privacy: .public) unavailable → used \(fallbackModel, privacy: .public)"
      )
      let text = try await send(
        systemPrompt: systemPrompt,
        userText: userText,
        model: fallbackModel,
        temperature: temperature
      )
      return RewriteOutcome(text: text, usedModelID: fallbackModel, requestedModelID: modelID)
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
