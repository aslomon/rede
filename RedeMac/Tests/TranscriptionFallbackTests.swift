import XCTest

@testable import Rede

final class TranscriptionFallbackTests: XCTestCase {
  private final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var allowed = true
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    func block() { lock.lock(); defer { lock.unlock() }; allowed = false }
    func isAllowed() -> Bool { lock.lock(); defer { lock.unlock() }; return allowed }
    func attempts() -> Int { lock.lock(); defer { lock.unlock() }; return count }
  }

  private func audioFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rede-fallback-test-\(UUID().uuidString).m4a")
    try Data([1, 2, 3]).write(to: url)
    return url
  }

  private func reply(_ request: URLRequest, status: Int, payload: String) throws -> (Data, URLResponse) {
    (Data(payload.utf8), try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
      httpVersion: nil, headerFields: nil)))
  }

  func testModelAndUnsupportedParameterErrorsRetryLegacyWireShapeOnce() async throws {
    let errors = [
      (404, "{}"),
      (400, #"{"error":{"code":"model_not_found"}}"#),
      (400, #"{"error":{"code":"unsupported_parameter","param":"keywords[]"}}"#),
      (400, #"{"error":{"message":"Unknown parameter: languages[]"}}"#)
    ]
    for (status, payload) in errors {
      let state = State()
      let url = try audioFile()
      let text = try await TranscriptionService.transcribe(audioURL: url,
        customTerms: ["rede"], language: "de", apiKey: "fixture", transport: { request in
          let body = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
          if state.next() == 1 { return try self.reply(request, status: status, payload: payload) }
          XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nwhisper-1\r\n"))
          XCTAssertTrue(body.contains("name=\"response_format\"\r\n\r\ntext\r\n"))
          XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nde\r\n"))
          XCTAssertTrue(body.contains("name=\"prompt\""))
          XCTAssertTrue(body.contains("rede"))
          XCTAssertFalse(body.contains("name=\"keywords[]\""))
          XCTAssertFalse(body.contains("name=\"languages[]\""))
          XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/plain")
          return try self.reply(request, status: 200, payload: "  Hallo  ")
        })
      XCTAssertEqual(text, "Hallo")
      XCTAssertEqual(state.attempts(), 2)
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
  }

  func testGeneralErrorsNeverRetryOrAcceptRawResponse() async throws {
    for status in [400, 401, 403, 429, 500] {
      let state = State()
      let url = try audioFile()
      do {
        _ = try await TranscriptionService.transcribe(audioURL: url, apiKey: "fixture",
          transport: { request in
            _ = state.next()
            return try self.reply(request, status: status,
              payload: #"{"error":{"message":"Request failed"}}"#)
          })
        XCTFail("Expected failure")
      } catch TranscriptionError.apiError { }
      XCTAssertEqual(state.attempts(), 1)
    }
  }

  func testLegacyFailureExhaustsSharedRetryBudget() async throws {
    let state = State()
    let url = try audioFile()
    do {
      _ = try await TranscriptionService.transcribe(audioURL: url, apiKey: "fixture",
        transport: { request in
          _ = state.next()
          return try self.reply(request, status: 404, payload: "{}")
        })
      XCTFail("Expected legacy failure")
    } catch TranscriptionError.apiError { }
    XCTAssertEqual(state.attempts(), 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testRemoteGateBlocksInitialAndFallbackAttempts() async throws {
    for initiallyAllowed in [false, true] {
      let state = State()
      if !initiallyAllowed { state.block() }
      let url = try audioFile()
      do {
        _ = try await TranscriptionService.transcribe(audioURL: url, apiKey: "fixture",
          isRemoteAllowed: { state.isAllowed() }, transport: { request in
            _ = state.next()
            state.block()
            return try self.reply(request, status: 404, payload: "{}")
          })
        XCTFail("Expected remote block")
      } catch let error as OpenAIRemotePolicyError {
        XCTAssertEqual(error, .remoteNotAllowed)
      }
      XCTAssertEqual(state.attempts(), initiallyAllowed ? 1 : 0)
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
  }

  func testCancellationBeforeLegacyFallbackDoesNotUploadAgain() async throws {
    let state = State()
    let url = try audioFile()
    let task = Task {
      try await TranscriptionService.transcribe(audioURL: url, apiKey: "fixture",
        transport: { request in
          _ = state.next()
          withUnsafeCurrentTask { $0?.cancel() }
          return try self.reply(request, status: 404, payload: "{}")
        })
    }
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    XCTAssertEqual(state.attempts(), 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testProductionEntryPointBlocksAndCleansAudioBeforeCredentialLookup() async throws {
    let url = try audioFile()
    do {
      _ = try await TranscriptionService.transcribe(audioURL: url, isRemoteAllowed: { false })
      XCTFail("Expected policy block")
    } catch is OpenAIRemotePolicyError { }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

}
