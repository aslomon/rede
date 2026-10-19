import XCTest

@testable import Rede

final class OpenAIRewriteRetryTests: XCTestCase {
  private final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var allowed = true
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    func block() { lock.lock(); defer { lock.unlock() }; allowed = false }
    func isAllowed() -> Bool { lock.lock(); defer { lock.unlock() }; return allowed }
    func attempts() -> Int { lock.lock(); defer { lock.unlock() }; return count }
  }

  private func reply(_ request: URLRequest, status: Int, payload: String) throws -> (Data, URLResponse) {
    let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
      httpVersion: nil, headerFields: nil))
    return (Data(payload.utf8), response)
  }

  private func body(_ request: URLRequest) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
  }

  func testNamedEffortRejectionRetriesOnlyTheModelDefault() async throws {
    for model in ["gpt-6-luna", "gpt-6-sol", "gpt-6.1-sol"] {
      for marker in [#""param":"reasoning_effort","message":"Unsupported value""#,
        #""message":"Unsupported reasoning_effort value""#] {
        let state = State()
        let provider = OpenAIRewriteProvider(modelID: model, reasoningEffort: .xhigh,
          apiKey: "fixture", transport: { request in
            let count = state.next()
            let payload = try self.body(request)
            XCTAssertEqual(payload["model"] as? String, model)
            XCTAssertNil(payload["temperature"])
            if count == 1 {
              XCTAssertEqual(request.timeoutInterval, 120)
              return try self.reply(request, status: 400, payload: "{\"error\":{\(marker)}}")
            }
            if model == "gpt-6-luna" {
              XCTAssertEqual(payload["reasoning_effort"] as? String, "none")
            } else { XCTAssertNil(payload["reasoning_effort"]) }
            XCTAssertEqual(request.timeoutInterval, 45)
            return try self.reply(request, status: 200,
              payload: #"{"choices":[{"message":{"content":"Hallo"}}]}"#)
          })
        let result = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTAssertFalse(result.didFallBack)
        XCTAssertEqual(state.attempts(), 2)
      }
    }
  }

  func testRetryBudgetNeverStacksEffortRetryAndModelFallback() async throws {
    for statuses in [[400, 404], [404, 400], [400, 400]] {
      let state = State()
      let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", reasoningEffort: .high,
        apiKey: "fixture", transport: { request in
          let count = state.next()
          return try self.reply(request, status: statuses[min(count - 1, 1)],
            payload: #"{"error":{"param":"reasoning_effort","message":"Rejected reasoning_effort"}}"#)
        })
      do {
        _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTFail("Expected the second failure to surface")
      } catch LLMError.modelUnavailable {
        XCTAssertEqual(statuses.last, 404)
      } catch LLMError.apiError(let message) {
        XCTAssertEqual(statuses.last, 400)
        XCTAssertEqual(message, "Rejected reasoning_effort")
      } catch { XCTFail("Expected public LLMError, received \(type(of: error))") }
      XCTAssertEqual(state.attempts(), 2)
    }
  }

  func testDefaultEffortAndLegacyModelDoNotRetryEffortErrors() async throws {
    for model in ["gpt-6-luna", "gpt-6-sol", "gpt-4o-mini"] {
      let state = State()
      let provider = OpenAIRewriteProvider(modelID: model, apiKey: "fixture", transport: { request in
        _ = state.next()
        return try self.reply(request, status: 400,
          payload: #"{"error":{"param":"reasoning_effort","message":"Rejected reasoning_effort"}}"#)
      })
      do {
        _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTFail("Expected parameter error")
      } catch LLMError.apiError { XCTAssertEqual(state.attempts(), 1) }
    }
  }

  func testRemoteGateRecheckedBeforeFallback() async throws {
    let state = State()
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture",
      isRemoteAllowed: { state.isAllowed() }, transport: { request in
        _ = state.next()
        state.block()
        return try self.reply(request, status: 404, payload: "{}")
      })
    do {
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      XCTFail("Expected remote block")
    } catch let error as OpenAIRemotePolicyError {
      XCTAssertEqual(error, .remoteNotAllowed)
    }
    XCTAssertEqual(state.attempts(), 1)
  }

  func testInitialRemoteBlockAndCancellationMakeZeroRequests() async throws {
    let state = State()
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture",
      isRemoteAllowed: { false }, transport: { request in
        _ = state.next()
        return try self.reply(request, status: 200, payload: "{}")
      })
    do {
      _ = try await provider.rewrite(systemPrompt: "private", userText: "private", temperature: 0.3)
      XCTFail("Expected block")
    } catch is OpenAIRemotePolicyError { }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
    }
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    XCTAssertEqual(state.attempts(), 0)
  }

  func testCancellationBeforeFallbackDoesNotSendSecondRequest() async throws {
    let state = State()
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture", transport: { request in
      _ = state.next()
      withUnsafeCurrentTask { $0?.cancel() }
      return try self.reply(request, status: 404, payload: "{}")
    })
    let task = Task {
      try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
    }
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    XCTAssertEqual(state.attempts(), 1)
  }

  func testTimeoutAndAuthenticationNeverRetry() async throws {
    let state = State()
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture", transport: { _ in
      _ = state.next()
      throw URLError(.timedOut)
    })
    do {
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      XCTFail("Expected timeout")
    } catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
    XCTAssertEqual(state.attempts(), 1)
    for status in [401, 403, 429, 500] {
      let attempts = State()
      let denied = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKey: "fixture", transport: { request in
        _ = attempts.next()
        return try self.reply(request, status: status,
          payload: #"{"error":{"message":"reasoning_effort unavailable"}}"#)
      })
      do {
        _ = try await denied.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
        XCTFail("Expected failure")
      } catch { XCTAssertEqual(attempts.attempts(), 1) }
    }
  }

  func testProductionInitializerBlocksBeforeCredentialLookup() async throws {
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", isRemoteAllowed: { false })
    do {
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      XCTFail("Expected policy block")
    } catch is OpenAIRemotePolicyError { }
  }

  func testEffortRetryRechecksGateAndCancellationBeforeSending() async throws {
    for cancel in [false, true] {
      let gateCalls = State(), requests = State()
      let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", reasoningEffort: .xhigh,
        apiKey: "fixture", isRemoteAllowed: {
          if gateCalls.next() == 2 {
            if cancel { withUnsafeCurrentTask { $0?.cancel() }; return true }
            return false
          }
          return true
        }, transport: { request in
          _ = requests.next()
          return try self.reply(request, status: 400,
            payload: #"{"error":{"param":"reasoning_effort","message":"Rejected reasoning_effort"}}"#)
        })
      let task = Task {
        try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      }
      do { _ = try await task.value; XCTFail("Expected terminal policy or cancellation") } catch is CancellationError {
        XCTAssertTrue(cancel)
      } catch is OpenAIRemotePolicyError { XCTAssertFalse(cancel) } catch {
        XCTFail("Unexpected error: \(type(of: error))")
      }
      XCTAssertEqual(gateCalls.attempts(), 2)
      XCTAssertEqual(requests.attempts(), 1)
    }
  }

}
