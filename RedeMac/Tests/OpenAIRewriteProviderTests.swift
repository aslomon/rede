import XCTest

@testable import Rede

final class OpenAIRewriteProviderTests: XCTestCase {
  private actor Requests {
    var values: [URLRequest] = []
    func record(_ request: URLRequest) -> Int {
      values.append(request)
      return values.count
    }
  }

  private func response(_ request: URLRequest, status: Int = 200) throws -> HTTPURLResponse {
    try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
      httpVersion: nil, headerFields: nil))
  }

  private func body(_ request: URLRequest) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
  }

  func testExplicitSupportedEffortsReachActualChatTransport() async throws {
    for model in ["gpt-6-luna", "gpt-6-sol"] {
      for effort in RewriteReasoningEffort.allCases {
        let provider = OpenAIRewriteProvider(
          modelID: model, reasoningEffort: effort, apiKey: "fixture-key", transport: { request in
            let payload = try self.body(request)
            XCTAssertEqual(payload["model"] as? String, model)
            XCTAssertEqual(payload["reasoning_effort"] as? String, effort.rawValue)
            XCTAssertNil(payload["temperature"])
            return (Data(#"{"choices":[{"message":{"content":"Hallo"}}]}"#.utf8),
              try self.response(request))
          })
        let result = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTAssertEqual(result.text, "Hallo")
        XCTAssertEqual(result.requestedModelID, model)
        XCTAssertEqual(result.usedModelID, model)
      }
    }
  }

  func testNilEffortUsesLunaDefaultAndPreservesLegacyOmission() async throws {
    for model in ["gpt-6-luna", "gpt-6.1-sol", "gpt-4o-mini", "unverified-custom-model"] {
      let provider = OpenAIRewriteProvider(modelID: model, apiKey: "fixture-key", transport: { request in
        let payload = try self.body(request)
        if model == "gpt-6-luna" {
          XCTAssertEqual(payload["reasoning_effort"] as? String, "none")
        } else { XCTAssertNil(payload["reasoning_effort"]) }
        if model.hasPrefix("gpt-6") { XCTAssertNil(payload["temperature"]) } else {
          XCTAssertEqual(payload["temperature"] as? Double, 0.3)
        }
        return (Data(#"{"choices":[{"message":{"content":"Hallo"}}]}"#.utf8),
          try self.response(request))
      })
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
    }
  }

  func testUnsupportedExplicitEffortIsRejectedBeforeTransportWithoutFallback() async throws {
    for model in ["gpt-6.1-sol", "gpt-4o-mini", "unverified-custom-model"] {
      let requests = Requests()
      let provider = OpenAIRewriteProvider(
        modelID: model, reasoningEffort: RewriteReasoningEffort.none,
        apiKey: "fixture-key", transport: { request in
          _ = await requests.record(request)
          return (Data(#"{"choices":[{"message":{"content":"Hallo"}}]}"#.utf8),
            try self.response(request))
        })
      do {
        _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTFail("Expected an unsupported effort to be rejected")
      } catch let error as OpenAIRewriteConfigurationError {
        XCTAssertEqual(error, .unsupportedReasoningEffort(modelID: model, effort: .none))
      }
      let attempts = await requests.values.count
      XCTAssertEqual(attempts, 0)
    }
  }

  func testSol61AcceptsHighAndXhighWithoutTemperature() async throws {
    for effort in [RewriteReasoningEffort.high, .xhigh] {
      let provider = OpenAIRewriteProvider(
        modelID: "gpt-6.1-sol", reasoningEffort: effort, apiKey: "fixture-key", transport: { request in
          let payload = try self.body(request)
          XCTAssertEqual(payload["reasoning_effort"] as? String, effort.rawValue)
          XCTAssertNil(payload["temperature"])
          return (Data(#"{"choices":[{"message":{"content":"Hallo"}}]}"#.utf8),
            try self.response(request))
        })
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
    }
  }

  func testFallbackRecomputesParametersForTheActualLegacyModel() async throws {
    let requests = Requests()
    let provider = OpenAIRewriteProvider(
      modelID: "gpt-6-luna", reasoningEffort: .xhigh, apiKey: "fixture-key", transport: { request in
        let attempt = await requests.record(request)
        let payload = try self.body(request)
        if attempt == 1 {
          XCTAssertEqual(payload["reasoning_effort"] as? String, "xhigh")
          XCTAssertNil(payload["temperature"])
          return (Data(#"{"error":{"code":"model_not_found","message":"Model does not exist"}}"#.utf8),
            try self.response(request, status: 404))
        }
        XCTAssertEqual(payload["model"] as? String, "gpt-4o-mini")
        XCTAssertNil(payload["reasoning_effort"])
        XCTAssertEqual(payload["temperature"] as? Double, 0.3)
        return (Data(#"{"choices":[{"message":{"content":"Fallback"}}]}"#.utf8),
          try self.response(request))
      })
    let result = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
    XCTAssertEqual(result.requestedModelID, "gpt-6-luna")
    XCTAssertEqual(result.usedModelID, "gpt-4o-mini")
    XCTAssertTrue(result.didFallBack)
    let attempts = await requests.values.count
    XCTAssertEqual(attempts, 2)
  }

  func testAPIParameterErrorDoesNotSilentlyRetryAnotherEffortOrModel() async throws {
    let requests = Requests()
    let provider = OpenAIRewriteProvider(
      modelID: "gpt-6-luna", reasoningEffort: .high, apiKey: "fixture-key", transport: { request in
        _ = await requests.record(request)
        return (Data(#"{"error":{"code":"invalid_request_error","message":"Unsupported parameter"}}"#.utf8),
          try self.response(request, status: 400))
      })
    do {
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      XCTFail("Expected API error")
    } catch LLMError.apiError(let message) {
      XCTAssertEqual(message, "Unsupported parameter")
    }
    let attempts = await requests.values.count
    XCTAssertEqual(attempts, 1)
  }
}
