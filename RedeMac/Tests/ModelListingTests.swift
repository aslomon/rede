import XCTest

@testable import Rede

final class ModelListingTests: XCTestCase {
  func testRemoteBlockPreventsTransport() async throws {
    do {
      _ = try await RewriteModelRegistry.fetchAvailableChatModels(apiKey: "fixture",
        isRemoteAllowed: { false }, transport: { _ in
          XCTFail("Blocked model listing must not send")
          throw URLError(.unknown)
        })
      XCTFail("Expected remote block")
    } catch let error as OpenAIRemotePolicyError { XCTAssertEqual(error, .remoteNotAllowed) }
  }

  func testModelListingFiltersAudioAndPreservesAccountGPT6Models() async throws {
    let models = try await RewriteModelRegistry.fetchAvailableChatModels(apiKey: "fixture",
      isRemoteAllowed: { true }, transport: { request in
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 30)
        let payload = """
          {"data":[{"id":"gpt-6-luna"},{"id":"gpt-transcribe"},{"id":"gpt-live-transcribe"},
          {"id":"gpt-4o-mini"},{"id":"gpt-6-luna"}]}
          """
        return (Data(payload.utf8), try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url),
          statusCode: 200, httpVersion: nil, headerFields: nil)))
      })
    XCTAssertEqual(models, ["gpt-4o-mini", "gpt-6-luna"])
  }

  func testProductionEntryPointHonorsBlockBeforeCredentialLookup() async throws {
    do {
      _ = try await RewriteModelRegistry.fetchAvailableChatModels(isRemoteAllowed: { false })
      XCTFail("Expected policy block")
    } catch is OpenAIRemotePolicyError { }
  }

  func testCancelledListingMakesNoRequest() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await RewriteModelRegistry.fetchAvailableChatModels(apiKey: "fixture",
        transport: { _ in XCTFail("Cancelled listing must not send"); throw URLError(.unknown) })
    }
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
  }

}
