import XCTest

@testable import Rede

final class TranscriptionCompatibilityTests: XCTestCase {
  private actor Attempts {
    var count = 0
    func next() -> Int { count += 1; return count }
  }

  private func audioFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rede-access-\(UUID()).m4a")
    try Data([1]).write(to: url)
    return url
  }

  private func reply(_ request: URLRequest, status: Int, payload: String) throws -> (Data, URLResponse) {
    (Data(payload.utf8), try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
      httpVersion: nil, headerFields: nil)))
  }

  func test403ModelNotFoundRetriesLegacyOnlyOnce() async throws {
    let attempts = Attempts(), url = try audioFile()
    let result = try await TranscriptionService.transcribe(audioURL: url,
      customTerms: ["<rede>"], apiKey: "fixture", transport: { request in
      if await attempts.next() == 1 {
        return try self.reply(request, status: 403, payload: #"{"error":{"code":"model_not_found"}}"#)
      }
      let body = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
      XCTAssertTrue(body.contains("Eigennamen und Begriffe: <rede>"))
      XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nwhisper-1\r\n"))
      return try self.reply(request, status: 200, payload: "Hallo")
    })
    XCTAssertEqual(result, "Hallo")
    let count = await attempts.count
    XCTAssertEqual(count, 2)
  }

  func testOnlyNamedUnsupportedModernParametersPermitCompatibilityRetry() async throws {
    let errors = [
      #"{"error":{"message":"Unsupported file format for model"}}"#,
      #"{"error":{"param":"languages[]","message":"Unsupported language: xx"}}"#,
      #"{"error":{"param":"file","code":"unsupported_parameter","message":"Unsupported parameter: file"}}"#,
      #"{"error":{"message":"Unknown model setting"}}"#
    ]
    for payload in errors {
      let attempts = Attempts(), url = try audioFile()
      do {
        _ = try await TranscriptionService.transcribe(audioURL: url, apiKey: "fixture", transport: { request in
          _ = await attempts.next()
          return try self.reply(request, status: 400, payload: payload)
        })
        XCTFail("Expected original error")
      } catch TranscriptionError.apiError { }
      let count = await attempts.count
      XCTAssertEqual(count, 1, payload)
    }
  }

  func testOtherStatusesNeverRetryEvenWhenErrorNamesUnavailableModel() async throws {
    for status in [401, 429, 500, 503] {
      let attempts = Attempts(), url = try audioFile()
      do {
        _ = try await TranscriptionService.transcribe(audioURL: url, apiKey: "fixture", transport: { request in
          _ = await attempts.next()
          return try self.reply(request, status: status, payload: #"{"error":{"code":"model_not_found"}}"#)
        })
        XCTFail("Expected status error")
      } catch TranscriptionError.apiError { }
      let count = await attempts.count
      XCTAssertEqual(count, 1)
    }
  }

  func testDeniedPolicyWinsBeforeAnyFileRead() async throws {
    let nonexistent = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).m4a")
    do {
      _ = try await TranscriptionService.transcribe(audioURL: nonexistent, apiKey: "fixture",
        isRemoteAllowed: { false }, transport: { _ in XCTFail("Unexpected upload"); throw URLError(.unknown) })
      XCTFail("Expected policy error before file read")
    } catch is OpenAIRemotePolicyError { }
  }

  func testTransportFailureDoesNotRetry() async throws {
    let attempts = Attempts(), url = try audioFile()
    do {
      _ = try await TranscriptionService.transcribe(audioURL: url, apiKey: "fixture", transport: { _ in
        _ = await attempts.next()
        throw URLError(.notConnectedToInternet)
      })
      XCTFail("Expected network error")
    } catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
    let count = await attempts.count
    XCTAssertEqual(count, 1)
  }
}
