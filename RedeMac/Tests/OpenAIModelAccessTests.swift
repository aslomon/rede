import XCTest

@testable import Rede

final class OpenAIModelAccessTests: XCTestCase {
  private actor Requests {
    var values: [URLRequest] = []
    func next(_ request: URLRequest) -> Int { values.append(request); return values.count }
  }

  private func reply(_ request: URLRequest, status: Int, payload: String) throws -> (Data, URLResponse) {
    (Data(payload.utf8), try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
      httpVersion: nil, headerFields: nil)))
  }

  func testExplicitModelNotFoundCodeOn403UsesSingleMiniFallback() async throws {
    let requests = Requests()
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", reasoningEffort: .high,
      apiKey: "fixture", transport: { request in
        if await requests.next(request) == 1 {
          return try self.reply(request, status: 403, payload: #"{"error":{"code":"model_not_found"}}"#)
        }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertEqual(body["temperature"] as? Double, 0.3)
        return try self.reply(request, status: 200,
          payload: #"{"choices":[{"message":{"content":"Hallo"}}]}"#)
      })
    let result = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
    XCTAssertEqual(result.requestedModelID, "gpt-6-luna")
    XCTAssertEqual(result.usedModelID, "gpt-4o-mini")
    let count = await requests.values.count
    XCTAssertEqual(count, 2)
  }

  func testAuthenticationRateLimitAndServerStatusesNeverRetryEvenWithModelCode() async throws {
    for status in [401, 429, 500, 503] {
      let requests = Requests()
      let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture", transport: { request in
        _ = await requests.next(request)
        return try self.reply(request, status: status, payload: #"{"error":{"code":"model_not_found"}}"#)
      })
      do {
        _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTFail("Expected status error")
      } catch LLMError.apiError { }
      let count = await requests.values.count
      XCTAssertEqual(count, 1)
    }
  }

  func test403WithoutExactModelCodeNeverRetries() async throws {
    for payload in [#"{"error":{"message":"model does not exist"}}"#,
      #"{"error":{"code":"permission_denied"}}"#, "{}"] {
      let requests = Requests()
      let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture", transport: { request in
        _ = await requests.next(request)
        return try self.reply(request, status: 403, payload: payload)
      })
      do {
        _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTFail("Expected permission error")
      } catch LLMError.apiError { }
      let count = await requests.values.count
      XCTAssertEqual(count, 1)
    }
  }

  func testPolicyErrorUsesExistingApprovedGermanDescription() {
    XCTAssertEqual(OpenAIRemotePolicyError.remoteNotAllowed.localizedDescription,
      "Online-Verarbeitung ist im sicheren lokalen Modus gesperrt.")
  }

  func testUnavailableMiniExhaustsTheSingleModelFallback() async throws {
    let requests = Requests()
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture", transport: { request in
      _ = await requests.next(request)
      return try self.reply(request, status: 403, payload: #"{"error":{"code":"model_not_found"}}"#)
    })
    do {
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      XCTFail("Expected unavailable fallback model")
    } catch LLMError.modelUnavailable(let model) { XCTAssertEqual(model, "gpt-4o-mini") }
    let count = await requests.values.count
    XCTAssertEqual(count, 2)
  }

}
