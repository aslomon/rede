import XCTest

@testable import Rede

final class TranscriptionServiceTests: XCTestCase {
  private actor Requests {
    var values: [URLRequest] = []
    func record(_ request: URLRequest) { values.append(request) }
  }

  private func audioFile(byteCount: Int = 4) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rede-transcription-test-\(UUID().uuidString).m4a")
    try Data(repeating: 1, count: byteCount).write(to: url)
    return url
  }

  private func response(_ request: URLRequest, status: Int = 200) throws -> HTTPURLResponse {
    try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status,
      httpVersion: nil, headerFields: nil))
  }

  func testRequestUsesCurrentFileModelJSONLanguageAndLiteralKeywords() async throws {
    let url = try audioFile()
    let requests = Requests()
    let text = try await TranscriptionService.transcribe(
      audioURL: url, customTerms: [" rede ", "AC-42", "<invalid>", "line\nbreak", ""],
      language: " de ", apiKey: "fixture-key", transport: { request in
        await requests.record(request)
        return (Data(#"{"text":"  Hallo  ","languages":[{"code":"de"}]}"#.utf8),
          try self.response(request))
      })
    let recorded = await requests.values
    let request = try XCTUnwrap(recorded.first)
    let body = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
    XCTAssertEqual(text, "Hallo")
    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    XCTAssertEqual(request.timeoutInterval, 120)
    XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
    XCTAssertTrue(body.contains("name=\"response_format\"\r\n\r\njson\r\n"))
    XCTAssertTrue(body.contains("name=\"languages[]\"\r\n\r\nde\r\n"))
    XCTAssertTrue(body.contains("name=\"keywords[]\"\r\n\r\nrede\r\n"))
    XCTAssertTrue(body.contains("name=\"keywords[]\"\r\n\r\nAC-42\r\n"))
    XCTAssertFalse(body.contains("name=\"language\""))
    XCTAssertFalse(body.contains("name=\"prompt\""))
    XCTAssertFalse(body.contains("name=\"temperature\""))
    XCTAssertFalse(body.contains("invalid"))
    XCTAssertFalse(body.contains("line\nbreak"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testAbsentLanguageAndTermsOmitOptionalFields() async throws {
    let url = try audioFile()
    _ = try await TranscriptionService.transcribe(
      audioURL: url, language: "  ", apiKey: "fixture-key", transport: { request in
        let body = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertFalse(body.contains("name=\"languages[]\""))
        XCTAssertFalse(body.contains("name=\"keywords[]\""))
        return (Data(#"{"text":"Hallo","languages":[]}"#.utf8), try self.response(request))
      })
  }

  func testEmptyMissingMalformedAndWrongTypeJSONFailWithoutReturningPayload() async throws {
    for payload in [#"{"text":"  "}"#, #"{"languages":[]}"#, "not-json", #"{"text":42}"#] {
      let url = try audioFile()
      do {
        _ = try await TranscriptionService.transcribe(
          audioURL: url, apiKey: "fixture-key", transport: { request in
            (Data(payload.utf8), try self.response(request))
          })
        XCTFail("Expected invalid transcript to fail")
      } catch TranscriptionError.apiError(let message) {
        XCTAssertEqual(message, "Transkription fehlgeschlagen")
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
  }

  func testAPIErrorPreservesMessageAndCleansAudio() async throws {
    let url = try audioFile()
    do {
      _ = try await TranscriptionService.transcribe(
        audioURL: url, apiKey: "fixture-key", transport: { request in
          (Data(#"{"error":{"message":"Quota exhausted"}}"#.utf8),
            try self.response(request, status: 429))
        })
      XCTFail("Expected API failure")
    } catch TranscriptionError.apiError(let message) {
      XCTAssertEqual(message, "Quota exhausted")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testAPIErrorWithoutJSONUsesStatus() async throws {
    let url = try audioFile()
    do {
      _ = try await TranscriptionService.transcribe(
        audioURL: url, apiKey: "fixture-key", transport: { request in
          (Data("upstream unavailable".utf8), try self.response(request, status: 503))
        })
      XCTFail("Expected API failure")
    } catch TranscriptionError.apiError(let message) {
      XCTAssertEqual(message, "Status 503")
    }
  }

  func testTransportErrorPropagatesAndCleansAudio() async throws {
    let url = try audioFile()
    do {
      _ = try await TranscriptionService.transcribe(
        audioURL: url, apiKey: "fixture-key", transport: { _ in
          throw URLError(.notConnectedToInternet)
        })
      XCTFail("Expected network failure")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .notConnectedToInternet)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testInvalidHTTPResponseFails() async throws {
    let url = try audioFile()
    do {
      _ = try await TranscriptionService.transcribe(
        audioURL: url, apiKey: "fixture-key", transport: { request in
          (Data(), URLResponse(url: try XCTUnwrap(request.url), mimeType: nil,
            expectedContentLength: 0, textEncodingName: nil))
        })
      XCTFail("Expected invalid HTTP response")
    } catch TranscriptionError.networkError { }
  }

  func testOversizedAudioFailsBeforeTransportAndCleansAudio() async throws {
    let url = try audioFile(byteCount: TranscriptionService.remoteUploadByteLimit + 1)
    let requests = Requests()
    do {
      _ = try await TranscriptionService.transcribe(
        audioURL: url, apiKey: "fixture-key", transport: { request in
          await requests.record(request)
          return (Data(), try self.response(request))
        })
      XCTFail("Expected upload-size failure")
    } catch TranscriptionError.fileTooLarge { }
    let attempts = await requests.values.count
    XCTAssertEqual(attempts, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertFalse(TranscriptionService.exceedsRemoteUploadLimit(
      byteCount: TranscriptionService.remoteUploadByteLimit))
    XCTAssertEqual(TranscriptionService.resourceTimeout, 600)
  }

  func testAlreadyCancelledTaskDoesNotUploadAndCleansAudio() async throws {
    let url = try audioFile()
    let requests = Requests()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await TranscriptionService.transcribe(
        audioURL: url, apiKey: "fixture-key", transport: { request in
          await requests.record(request)
          return (Data(#"{"text":"Hallo"}"#.utf8), try self.response(request))
        })
    }
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    let attempts = await requests.values.count
    XCTAssertEqual(attempts, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testInFlightCancellationReachesTransportAndCleansAudio() async throws {
    let url = try audioFile()
    let started = expectation(description: "Transport started")
    let task = Task {
      try await TranscriptionService.transcribe(
        audioURL: url, apiKey: "fixture-key", transport: { request in
          started.fulfill()
          try await Task.sleep(nanoseconds: 2_000_000_000)
          return (Data(#"{"text":"Hallo"}"#.utf8), try self.response(request))
        })
    }
    await fulfillment(of: [started], timeout: 3)
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }
}
