import XCTest

@testable import Rede

final class RewriteReasoningEffortTests: XCTestCase {
  func testUnsupportedEffortHasActionableGermanLocalizedDescription() {
    let error = OpenAIRewriteConfigurationError.unsupportedReasoningEffort(
      modelID: "gpt-6.1-sol", effort: .none)
    XCTAssertEqual(error.localizedDescription,
      "Modell gpt-6.1-sol unterstützt den Denkaufwand none nicht.")
  }

  func testDocumentedEffortsCodableRoundTripWithoutInventingValues() throws {
    XCTAssertEqual(RewriteReasoningEffort.allCases.map(\.rawValue),
      ["none", "low", "medium", "high", "xhigh", "max"])
    for effort in RewriteReasoningEffort.allCases {
      let decoded = try JSONDecoder().decode(
        RewriteReasoningEffort.self, from: JSONEncoder().encode(effort))
      XCTAssertEqual(decoded, effort)
    }
    XCTAssertThrowsError(try JSONDecoder().decode(
      RewriteReasoningEffort.self, from: Data(#""minimal""#.utf8)))
  }

  func testVerifiedCapabilitiesExcludeUnverifiedModelsAndUnsupportedNone() {
    for model in ["gpt-6-luna", "gpt-6-sol"] {
      XCTAssertEqual(RewriteModelRegistry.option(for: model).supportedReasoningEfforts,
        RewriteReasoningEffort.allCases)
    }
    XCTAssertEqual(RewriteModelRegistry.option(for: "gpt-6.1-sol").supportedReasoningEfforts,
      [.low, .medium, .high, .xhigh, .max])
    for model in ["gpt-4o-mini", "gpt-5.4", "gpt-6-luna-unverified-snapshot", "custom"] {
      XCTAssertTrue(RewriteModelRegistry.option(for: model).supportedReasoningEfforts.isEmpty)
    }
  }
}
