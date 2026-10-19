import XCTest

@testable import Rede

final class RewriteModelRegistryTests: XCTestCase {
  func testVerifiedGPT6RewriteModelsAreCuratedWithoutTemperature() throws {
    for id in ["gpt-6-luna", "gpt-6-sol", "gpt-6.1-sol"] {
      let model = try XCTUnwrap(RewriteModelRegistry.curated.first { $0.id == id })
      XCTAssertNotEqual(model.label, id)
      XCTAssertFalse(model.supportsTemperature)
      XCTAssertFalse(RewriteModelRegistry.supportsTemperature(id))
    }
  }

  func testGPT6SnapshotsAndFetchedModelsAlsoOmitTemperature() {
    XCTAssertFalse(RewriteModelRegistry.supportsTemperature("gpt-6-luna-2026-09-22"))
    XCTAssertFalse(RewriteModelRegistry.supportsTemperature("GPT-6.1-SOL"))
    XCTAssertTrue(RewriteModelRegistry.supportsTemperature("gpt-4o-mini"))
    let ids = RewriteModelRegistry.options(includingFetched: ["gpt-6-luna"]).map(\.id)
    XCTAssertEqual(ids.filter { $0 == "gpt-6-luna" }.count, 1)
  }

  func testVerifiedMetadataAdditionPreservesExistingDefaults() {
    XCTAssertEqual(RewriteModelRegistry.defaultModelID, "gpt-4o")
    XCTAssertEqual(RewriteModelRegistry.fastModelID, "gpt-4o-mini")
    XCTAssertEqual(RewriteModelRegistry.strongModelID, "gpt-5.4")
    XCTAssertEqual(RewriteModelRegistry.safeFallbackModelID, "gpt-4o-mini")
  }

  func testRecommendedModelPreservesLegacyOrderAndResolutionDefaults() {
    XCTAssertEqual(RewriteModelRegistry.recommendedModelID, "gpt-6-luna")
    XCTAssertEqual(RewriteModelRegistry.curated.first?.tier, "Sehr schnell & günstig")
    XCTAssertEqual(Array(RewriteModelRegistry.curated.dropFirst().prefix(5).map(\.id)),
      ["gpt-4o-mini", "gpt-4o", "gpt-5.4-mini", "gpt-5.4", "gpt-5.5"])
    XCTAssertEqual(RewriteModelRegistry.selectableEfforts(for: "gpt-6-luna"),
      [.none, .medium, .high, .xhigh])
    for model in ["gpt-6-luna", "gpt-6-sol", "gpt-6.1-sol", "gpt-4o", "unknown"] {
      for effort in RewriteReasoningEffort.allCases {
        let supported = RewriteModelRegistry.supportedEfforts(for: model).contains(effort)
        let expected = supported ? effort : RewriteModelRegistry.resolvedEffort(modelID: model, stored: nil)
        XCTAssertEqual(RewriteModelRegistry.resolvedEffort(modelID: model, stored: effort), expected)
      }
    }
    XCTAssertEqual(RewriteModelRegistry.resolvedEffort(modelID: "gpt-6-luna", stored: nil),
      RewriteReasoningEffort.none)
    for model in ["gpt-6-sol", "gpt-6.1-sol", "gpt-4o", "unknown"] {
      XCTAssertNil(RewriteModelRegistry.resolvedEffort(modelID: model, stored: nil))
    }
  }

  func testRequestAndResourceTimeoutsAllowChosenReasoningEffort() {
    let cases: [(RewriteReasoningEffort?, TimeInterval)] = [
      (nil, 45), (RewriteReasoningEffort.none, 45), (.low, 45), (.medium, 60),
      (.high, 75), (.xhigh, 120), (.max, 120)
    ]
    for (effort, seconds) in cases {
      XCTAssertEqual(RewriteModelRegistry.requestTimeout(for: effort), seconds)
      XCTAssertEqual(RewriteModelRegistry.resourceTimeout(for: effort), seconds)
      let configuration = OpenAIRewriteProvider.sessionConfiguration(for: effort)
      XCTAssertEqual(configuration.timeoutIntervalForRequest, seconds)
      XCTAssertEqual(configuration.timeoutIntervalForResource, seconds)
      XCTAssertNil(configuration.urlCache)
      XCTAssertNil(configuration.httpCookieStorage)
    }
  }

}
