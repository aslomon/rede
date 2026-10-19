import XCTest

@testable import Rede

final class PurposeRoutingTests: XCTestCase {
    private let context = DecisionContext(dictatedText: "Please move our meeting to Wednesday.")

    func testRoutesOnlyAllowedChoiceAtConfiguredConfidenceAndMargin() async {
        let router = DecisionsPurposeRouter(client: client(choice: "email", confidence: 0.61, top: 0.74))
        let result = await router.route(context)
        XCTAssertEqual(result.purpose, .email)
        XCTAssertNil(result.neutralReason)
        let unsure = await DecisionsPurposeRouter(client: client(choice: "email", confidence: 0.4)).route(context)
        XCTAssertEqual(unsure.neutralReason, .lowConfidence)
        let close = await DecisionsPurposeRouter(client: client(choice: "email", top: 0.40)).route(context)
        XCTAssertEqual(close.neutralReason, .lowMargin)
    }

    func testSelectedChoiceMustHaveTheHighestProbability() async {
        let result = await DecisionsPurposeRouter(client: client(choice: "email", top: 0.05)).route(context)
        XCTAssertEqual(result.purpose, .other)
        XCTAssertEqual(result.neutralReason, .invalidChoice)
    }

    func testOtherRefusalInvalidAndUnavailableResponsesStayNeutral() async {
        for (choice, reason) in [("other", NeutralReason?.none), ("unoffered", .invalidChoice)] {
            let result = await DecisionsPurposeRouter(client: client(choice: choice)).route(context)
            XCTAssertEqual(result.purpose, .other)
            XCTAssertEqual(result.neutralReason, reason)
        }
        let refusal = DecisionsClient { _ in
            DecisionsHTTPResponse(
                data: Data("{\"answers\":[{\"type\":\"refusal\",\"name\":\"purpose\"}]}".utf8), statusCode: 200)
        }
        let refused = await DecisionsPurposeRouter(client: refusal).route(context)
        XCTAssertEqual(refused.neutralReason, .refusal)
        for (error, reason) in [(DecisionsClientError.notConfigured, NeutralReason.noAPIKey), (.timedOut, .timeout)] {
            let failed = await DecisionsPurposeRouter(client: DecisionsClient { _ in throw error }).route(context)
            XCTAssertEqual(failed.neutralReason, reason)
        }
    }

    func testGateAndShortDictationNeverReachTransport() async {
        let client = DecisionsClient { _ in
            XCTFail("Unexpected remote request")
            throw DecisionsClientError.invalidResponse
        }
        let blocked = await DecisionsPurposeRouter(client: client, isRemoteAllowed: { false }).route(context)
        XCTAssertEqual(blocked.neutralReason, .remoteNotAllowed)
        let short = await DecisionsPurposeRouter(client: client).route(DecisionContext(dictatedText: "Two words"))
        XCTAssertEqual(short.neutralReason, .tooShort)
    }

    func testCancellationIsTerminalAndTimeoutIsNeutral() async {
        let client = DecisionsClient { _ in
            try await Task.sleep(for: .seconds(10))
            throw CancellationError()
        }
        var policy = PurposeRoutingPolicy()
        policy.timeout = .milliseconds(20)
        let timedOut = await DecisionsPurposeRouter(client: client, policy: policy).route(context)
        XCTAssertEqual(timedOut.neutralReason, .timeout)
        let router = DecisionsPurposeRouter(client: client)
        let task = Task { await router.route(context) }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled.isCancelled)
    }

    func testInputContainsOnlyBoundedApprovedSectionsAndNoControlCharactersOrURLs() async {
        let client = DecisionsClient { body in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let input = try XCTUnwrap(object["input"] as? String)
            XCTAssertLessThanOrEqual(input.unicodeScalars.count, 4000)
            XCTAssertTrue(input.contains("App:"))
            XCTAssertTrue(input.contains("Selected text:"))
            XCTAssertTrue(input.contains("Field text:"))
            XCTAssertTrue(input.contains("Dictation:"))
            XCTAssertFalse(input.contains("https://private.invalid"))
            XCTAssertFalse(input.contains("\u{0001}"))
            let questions = try XCTUnwrap(object["questions"] as? [[String: Any]])
            XCTAssertEqual(questions[0]["name"] as? String, "purpose")
            let choices = try XCTUnwrap(questions[0]["choices"] as? [[String: Any]])
            XCTAssertEqual(choices.compactMap { $0["value"] as? String }, ["email", "ai_prompt", "other"])
            return DecisionsHTTPResponse(
                data: Data("{\"answers\":[{\"type\":\"refusal\",\"name\":\"purpose\"}]}".utf8), statusCode: 200)
        }
        let context = DecisionContext(
            dictatedText: String(repeating: "word ", count: 1000),
            selectedText: String(repeating: "S", count: 2000), appName: "Mail\u{0001} https://private.invalid",
            fieldText: String(repeating: "F", count: 2000))
        _ = await DecisionsPurposeRouter(client: client).route(context)
    }

    func testOverlaysAreBoundedAppendOnlyAndOtherIsIdentical() {
        XCTAssertEqual(PurposeOverlay.apply(.other, to: "BASE"), "BASE")
        for purpose in [DictationPurpose.email, .aiPrompt] {
            let prompt = PurposeOverlay.apply(purpose, to: "BASE")
            XCTAssertTrue(prompt.hasPrefix("BASE"))
            XCTAssertLessThanOrEqual(prompt.count - 4, 600)
            XCTAssertTrue(prompt.contains("facts"))
        }
    }

    private func client(choice: String, confidence: Double = 0.9, top: Double = 0.9) -> DecisionsClient {
        DecisionsClient { _ in
            let probabilities = ["email", "ai_prompt", "other"].map { value in
                ["value": value, "probability": value == choice ? top : (1 - top) / 2] as [String: Any]
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "answers": [
                    [
                        "type": "choice", "name": "purpose",
                        "choice": choice, "confidence": confidence, "probabilities": probabilities
                    ]
                ]
            ])
            return DecisionsHTTPResponse(data: data, statusCode: 200)
        }
    }
}
