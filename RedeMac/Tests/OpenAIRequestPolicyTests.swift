import XCTest

@testable import Rede

final class OpenAIRequestPolicyTests: XCTestCase {
  private final class Counts: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
  }

  func testDeniedPolicyDoesNotLookUpAnyCredentials() async throws {
    let keys = Counts(), sends = Counts()
    let key: @Sendable () -> String? = { _ = keys.next(); return "fixture" }
    let transport: OpenAIRewriteProvider.Transport = { _ in _ = sends.next(); throw URLError(.unknown) }
    let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKeyProvider: key,
      isRemoteAllowed: { false }, transport: transport)
    do {
      _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      XCTFail("Expected policy error")
    } catch is OpenAIRemotePolicyError { }
    do {
      _ = try await RewriteModelRegistry.fetchAvailableChatModels(apiKeyProvider: key,
        isRemoteAllowed: { false }, transport: transport)
      XCTFail("Expected policy error")
    } catch is OpenAIRemotePolicyError { }
    do {
      _ = try await TranscriptionService.transcribe(
        audioURL: URL(fileURLWithPath: "/nonexistent/rede-policy-fixture.m4a"), apiKeyProvider: key,
        isRemoteAllowed: { false }, transport: transport)
      XCTFail("Expected policy error before file I/O")
    } catch is OpenAIRemotePolicyError { }
    XCTAssertEqual(keys.value, 0)
    XCTAssertEqual(sends.value, 0)
  }

  func testCancellationInsidePolicyPreventsCredentialLookupAndSend() async {
    let keys = Counts(), sends = Counts()
    let key: @Sendable () -> String? = { _ = keys.next(); return "fixture" }
    let gate: @Sendable () -> Bool = { withUnsafeCurrentTask { $0?.cancel() }; return true }
    let transport: OpenAIRewriteProvider.Transport = { _ in _ = sends.next(); throw URLError(.unknown) }
    let tasks: [Task<Void, Error>] = [
      Task {
        let provider = OpenAIRewriteProvider(modelID: "gpt-6-luna", apiKeyProvider: key,
          isRemoteAllowed: gate, transport: transport)
        _ = try await provider.rewrite(systemPrompt: "system", userText: "text", temperature: 0.3)
      },
      Task {
        _ = try await RewriteModelRegistry.fetchAvailableChatModels(apiKeyProvider: key,
          isRemoteAllowed: gate, transport: transport)
      },
      Task {
        _ = try await TranscriptionService.transcribe(
          audioURL: URL(fileURLWithPath: "/nonexistent/rede-policy-fixture.m4a"), apiKeyProvider: key,
          isRemoteAllowed: gate, transport: transport)
      }
    ]
    for task in tasks {
      do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { } catch {
        XCTFail("Expected CancellationError, received \(type(of: error))")
      }
    }
    XCTAssertEqual(keys.value, 0)
    XCTAssertEqual(sends.value, 0)
  }

  func testCancellationAtTranscriptionRequestBoundaryPreventsCredentialLookup() async throws {
    let keys = Counts(), gateCalls = Counts(), sends = Counts()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rede-policy-\(UUID()).m4a")
    try Data([1]).write(to: url)
    let task = Task {
      try await TranscriptionService.transcribe(audioURL: url,
        apiKeyProvider: { _ = keys.next(); return "fixture" },
        isRemoteAllowed: {
          if gateCalls.next() == 2 { withUnsafeCurrentTask { $0?.cancel() } }
          return true
        }, transport: { _ in _ = sends.next(); throw URLError(.unknown) })
    }
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    XCTAssertEqual(gateCalls.value, 2)
    XCTAssertEqual(keys.value, 0)
    XCTAssertEqual(sends.value, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

}
