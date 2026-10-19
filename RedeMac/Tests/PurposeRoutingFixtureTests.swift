import XCTest
@testable import Rede

final class PurposeRoutingFixtureTests: XCTestCase {
    func testFrozenThresholdsReplay71RealProductionRouteResponsesWithoutNegativeOverlays() async throws {
        let policy = PurposeRoutingPolicy()
        XCTAssertEqual(policy.minConfidence, 0.55)
        XCTAssertEqual(policy.minMargin, 0.15)
        XCTAssertEqual(policy.minWords, 4)
        XCTAssertEqual(policy.timeout, .seconds(2.5))
        let fixtures = try loadFixtures()
        XCTAssertEqual(fixtures.count, 71)
        var falsePositives = 0
        var emailRecall = 0
        var promptRecall = 0
        for fixture in fixtures {
            let requestData = try JSONSerialization.data(withJSONObject: XCTUnwrap(fixture["request"]))
            let response = try JSONSerialization.data(withJSONObject: XCTUnwrap(fixture["response"]))
            let context = try context(fixture)
            let client = DecisionsClient { body in
                let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
                XCTAssertTrue(NSDictionary(dictionary: actual).isEqual(to: expected))
                return DecisionsHTTPResponse(data: response, statusCode: 200)
            }
            let decision = await DecisionsPurposeRouter(client: client, policy: policy).route(context)
            let id = try XCTUnwrap(fixture["id"] as? String)
            XCTAssertEqual(decision.purpose.rawValue, fixture["routedPurpose"] as? String, id)
            XCTAssertEqual(decision.neutralReason?.rawValue, fixture["neutralReason"] as? String, id)
            let expected = try XCTUnwrap(fixture["expected"] as? String)
            if expected == "other", decision.purpose != .other { falsePositives += 1 }
            if expected == "email", decision.purpose == .email { emailRecall += 1 }
            if expected == "ai_prompt", decision.purpose == .aiPrompt { promptRecall += 1 }
        }
        XCTAssertEqual(falsePositives, 0)
        XCTAssertEqual(emailRecall, 21)
        XCTAssertEqual(promptRecall, 20)
    }

    private func context(_ fixture: [String: Any]) throws -> DecisionContext {
        DecisionContext(dictatedText: try XCTUnwrap(fixture["dictatedText"] as? String),
                        selectedText: fixture["selectedText"] as? String,
                        appName: fixture["appName"] as? String, fieldText: fixture["fieldText"] as? String)
    }

    private func loadFixtures() throws -> [[String: Any]] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "purpose-routing-real-71", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }
}
