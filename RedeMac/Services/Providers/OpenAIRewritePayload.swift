import Foundation

struct OpenAIRewriteRequest: Encodable {
  struct Message: Encodable {
    let role: String
    let content: String
  }
  let model: String
  let messages: [Message]
  let temperature: Double?
  let reasoningEffort: RewriteReasoningEffort?

  enum CodingKeys: String, CodingKey {
    case model, messages, temperature
    case reasoningEffort = "reasoning_effort"
  }
}

struct OpenAIRewriteResponseMessage: Decodable { let content: String? }

struct OpenAIRewriteResponse: Decodable {
  struct Choice: Decodable {
    let message: OpenAIRewriteResponseMessage?
  }
  let choices: [Choice]?
}

struct OpenAIErrorResponse: Decodable {
  struct APIError: Decodable {
    let message: String?
    let code: String?
    let param: String?

    var namesReasoningEffort: Bool {
      param == "reasoning_effort" || message?.lowercased().contains("reasoning_effort") == true
    }

    var isModelUnavailable: Bool {
      code == "model_not_found"
        || (message?.lowercased().contains("model") == true
          && message?.lowercased().contains("does not exist") == true)
    }
  }
  let error: APIError?
}
