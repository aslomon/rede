import XCTest

@testable import Blitztext

final class LlamaCppServerClientTests: XCTestCase {
  func testHealthDecodingTreats200AsReady() throws {
    let response = try LlamaCppServerClient.healthStatus(
      statusCode: 200,
      data: Data(#"{"status":"ok"}"#.utf8)
    )

    XCTAssertEqual(response, .ready)
  }

  func testHealthDecodingTreats503AsLoading() throws {
    let response = try LlamaCppServerClient.healthStatus(
      statusCode: 503,
      data: Data(#"{"status":"loading model"}"#.utf8)
    )

    XCTAssertEqual(response, .loading)
  }

  func testChatRequestTargetsOpenAICompatibleEndpointWithApiKey() throws {
    let client = LlamaCppServerClient(
      baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:49001")),
      apiKey: "session-token"
    )

    let request = try client.makeChatRequest(
      modelID: "qwen3",
      systemPrompt: "system",
      userText: "user",
      temperature: 0.2
    )

    XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:49001/v1/chat/completions")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.httpMethod, "POST")
    let body = try XCTUnwrap(request.httpBody)
    let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
    XCTAssertTrue(bodyString.contains(#""stream":false"#))
    XCTAssertTrue(bodyString.contains(#""temperature":0.2"#))
  }

  func testChatResponseTrimsContent() throws {
    let data = Data(#"{"choices":[{"message":{"content":"  Hallo  "}}]}"#.utf8)

    let text = try LlamaCppServerClient.decodeChatContent(data)

    XCTAssertEqual(text, "Hallo")
  }

  func testEmptyChatResponseThrowsNoContent() {
    let data = Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8)

    XCTAssertThrowsError(try LlamaCppServerClient.decodeChatContent(data)) { error in
      guard case LLMError.noContent = error else {
        return XCTFail("Expected LLMError.noContent, got \(error)")
      }
    }
  }
}
