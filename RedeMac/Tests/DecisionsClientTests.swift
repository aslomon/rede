import XCTest

@testable import Rede

final class DecisionsClientTests: XCTestCase {
    private let question = DecisionChoiceQuestion(
        name: "synthetic_route", instructions: "Classify supplied synthetic evidence.",
        choices: [
            DecisionChoiceOption(value: .string("mode-email"), description: "Email draft."),
            DecisionChoiceOption(value: .string("mode-dictation")),
            DecisionChoiceOption(value: .string("other"))
        ])

    private let realShape = """
        {"model":"gpt-6-luna","answers":[{"type":"choice","name":"synthetic_route",
        "choice":"mode-email","probabilities":[{"value":"mode-email","probability":0.74},
        {"value":"mode-dictation","probability":0.26},{"value":"other","probability":0.0}],
        "confidence":0.61}],"usage":{"input_tokens":173,"output_tokens":0,"total_tokens":173}}
        """

    func testDecodesActualSyntheticAPIResponseWithoutApplyingConfidenceThreshold() async throws {
        let result = try await client().choose(input: "Synthetic text.", question: question)
        guard case .choice(let answer) = result else { return XCTFail("Expected typed choice") }
        XCTAssertEqual(answer.choice, .string("mode-email"))
        XCTAssertEqual(answer.confidence, 0.61)
        XCTAssertEqual(answer.probabilities.map(\.probability), [0.74, 0.26, 0])
    }

    func testEncodesExactEndpointPayloadWithoutAddingRoutingInstructions() async throws {
        let response = Data(realShape.utf8)
        let client = DecisionsClient { body in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["model", "input", "questions"])
            XCTAssertEqual(object["model"] as? String, "gpt-6-luna")
            XCTAssertEqual(object["input"] as? String, "SYNTHETIC_INPUT")
            let questions = try XCTUnwrap(object["questions"] as? [[String: Any]])
            XCTAssertEqual(questions.count, 1)
            XCTAssertEqual(questions[0]["type"] as? String, "choice")
            XCTAssertEqual(questions[0]["instructions"] as? String, "Classify supplied synthetic evidence.")
            let choices = try XCTUnwrap(questions[0]["choices"] as? [[String: Any]])
            XCTAssertEqual(choices[0]["value"] as? String, "mode-email")
            XCTAssertEqual(choices[0]["description"] as? String, "Email draft.")
            XCTAssertNil(choices[1]["description"])
            return DecisionsHTTPResponse(data: response, statusCode: 200)
        }
        _ = try await client.choose(input: "SYNTHETIC_INPUT", question: question)
    }

    func testRefusalIsTypedAndDoesNotTriggerAnotherRequest() async throws {
        let log = DecisionsCallCounter()
        let client = DecisionsClient { _ in
            await log.record()
            return DecisionsHTTPResponse(
                data: Data("{\"answers\":[{\"type\":\"refusal\",\"name\":\"synthetic_route\"}]}".utf8),
                statusCode: 200)
        }
        let result = try await client.choose(input: "Synthetic evidence.", question: question)
        XCTAssertEqual(result, .refusal)
        let calls = await log.count
        XCTAssertEqual(calls, 1)
    }

    func testRejectsUnknownChoiceAndBooleanInsteadOfString() async {
        for replacement in ["\"unoffered-mode\"", "true", "null", "3"] {
            let response = realShape.replacingOccurrences(
                of: "\"choice\":\"mode-email\"", with: "\"choice\":\(replacement)")
            await assertFailure(.invalidResponse, client: client(response: response))
        }
    }

    func testRejectsMissingNonNumericAndOutOfRangeConfidence() async {
        for replacement in ["null", "\"0.61\"", "-0.1", "1.1", "1e999"] {
            let response = realShape.replacingOccurrences(
                of: "\"confidence\":0.61", with: "\"confidence\":\(replacement)")
            await assertFailure(.invalidResponse, client: client(response: response))
        }
        await assertFailure(
            .invalidResponse,
            client: client(
                response:
                    realShape.replacingOccurrences(of: "\"confidence\":0.61", with: "\"ignored\":0.61")))
    }

    func testRejectsWrongNameWrongTypeAndMalformedJSON() async {
        for response in [
            "{", "[]", "{\"answers\":null}", "{\"answers\":[]}",
            realShape.replacingOccurrences(of: "synthetic_route", with: "another_question"),
            realShape.replacingOccurrences(of: "\"type\":\"choice\"", with: "\"type\":\"predicate\"")
        ] {
            await assertFailure(.invalidResponse, client: client(response: response))
        }
    }

    func testRejectsMissingDuplicateUnknownAndInvalidProbabilities() async {
        let values = [
            "null", "[]", "[{\"value\":\"mode-email\",\"probability\":1}]",
            "[{\"value\":\"mode-email\",\"probability\":1},"
                + "{\"value\":\"mode-email\",\"probability\":0},{\"value\":\"other\",\"probability\":0}]"
        ]
        for probabilities in values {
            let response =
                "{\"answers\":[{\"type\":\"choice\",\"name\":\"synthetic_route\",\"choice\":\"mode-email\","
                + "\"confidence\":0.9,\"probabilities\":\(probabilities)}]}"
            await assertFailure(.invalidResponse, client: client(response: response))
        }
        for replacement in ["1.4", "-0.1", "null", "\"0.74\"", "1e999"] {
            await assertFailure(
                .invalidResponse,
                client: client(
                    response:
                        realShape.replacingOccurrences(
                            of: "\"probability\":0.74", with: "\"probability\":\(replacement)")))
        }
        await assertFailure(
            .invalidResponse,
            client: client(
                response:
                    realShape.replacingOccurrences(of: "\"value\":\"other\"", with: "\"value\":\"unknown\"")))
    }

    func testRejectsAmbiguousMultipleAnswers() async {
        let answer = "{\"type\":\"refusal\",\"name\":\"synthetic_route\"}"
        await assertFailure(.invalidResponse, client: client(response: "{\"answers\":[\(answer),\(answer)]}"))
    }

    func testRejectsProbabilityArraysThatAreNotDistributions() async {
        for replacement in ["0.0", "1.0"] {
            await assertFailure(
                .invalidResponse,
                client: client(
                    response:
                        realShape.replacingOccurrences(
                            of: "\"probability\":0.74", with: "\"probability\":\(replacement)")))
        }
    }

    func testInputAndQuestionValidationHappensBeforeTransport() async {
        let invalidQuestions = [
            DecisionChoiceQuestion(name: "", instructions: "Question", choices: question.choices),
            DecisionChoiceQuestion(name: "route", instructions: " ", choices: question.choices),
            DecisionChoiceQuestion(name: "route", instructions: "Question", choices: []),
            DecisionChoiceQuestion(name: "route", instructions: "Question", choices: [question.choices[0]]),
            DecisionChoiceQuestion(
                name: "route", instructions: "Question", choices: [question.choices[0], question.choices[0]]),
            DecisionChoiceQuestion(
                name: "route", instructions: "Question",
                choices: (0..<256).map {
                    DecisionChoiceOption(value: .string("choice-\($0)"))
                })
        ]
        let neverTransport = DecisionsClient { _ in
            XCTFail("Invalid input reached transport")
            throw DecisionsClientError.networkUnavailable
        }
        for invalid in invalidQuestions {
            await assertFailure(.invalidRequest, client: neverTransport, input: "text", question: invalid)
        }
        for input in [" ", String(repeating: "x", count: DecisionsClient.maximumInputBytes + 1)] {
            await assertFailure(.invalidRequest, client: neverTransport, input: input)
        }
    }

    func testTypedBooleanAndStringValuesRemainDistinct() async throws {
        let question = DecisionChoiceQuestion(
            name: "typed", instructions: "Synthetic predicate choice.",
            choices: [
                DecisionChoiceOption(value: .boolean(true)), DecisionChoiceOption(value: .string("true"))
            ])
        let client = client(
            response:
                "{\"answers\":[{\"type\":\"choice\",\"name\":\"typed\",\"choice\":true,\"confidence\":1,"
                + "\"probabilities\":[{\"value\":true,\"probability\":1},{\"value\":\"true\",\"probability\":0}]}]}"
        )
        guard case .choice(let answer) = try await client.choose(input: "Synthetic text", question: question) else {
            return XCTFail("Expected boolean choice")
        }
        XCTAssertEqual(answer.choice, .boolean(true))
    }

    func testMapsHTTPFailuresWithoutReflectingSensitiveResponseBody() async {
        for (status, expected) in [
            (401, DecisionsClientError.unauthorized), (403, .unauthorized),
            (429, .rateLimited), (500, .serviceUnavailable), (408, .timedOut), (504, .timedOut),
            (418, .httpStatus(418))
        ] {
            await assertFailure(expected, client: client(response: "SENSITIVE_SERVER_BODY", status: status))
            XCTAssertFalse(expected.localizedDescription.contains("SENSITIVE_SERVER_BODY"))
        }
    }

    func testMapsTimeoutAndNetworkErrors() async {
        for (code, expected) in [
            (URLError.timedOut, DecisionsClientError.timedOut),
            (URLError.notConnectedToInternet, .networkUnavailable)
        ] {
            await assertFailure(expected, client: DecisionsClient { _ in throw URLError(code) })
        }
    }

    func testCancellationPropagatesAndDoesNotReturnLateDecision() async {
        let client = DecisionsClient { _ in
            try await Task.sleep(for: .seconds(10))
            throw DecisionsClientError.invalidResponse
        }
        let task = Task { try await client.choose(input: "Synthetic text", question: question) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled request returned")
        } catch { XCTAssertTrue(error is CancellationError) }
        let urlCancelled = DecisionsClient { _ in throw URLError(.cancelled) }
        do {
            _ = try await urlCancelled.choose(input: "Synthetic text", question: question)
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testLateTransportReturnAfterCancellationIsSuppressed() async {
        let reply = Data(realShape.utf8)
        let client = DecisionsClient { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return DecisionsHTTPResponse(data: reply, statusCode: 200)
        }
        let task = Task { try await client.choose(input: "Synthetic text", question: question) }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellingInFlightRequestCancelsItsTransport() async {
        let started = expectation(description: "Synthetic transport started")
        let cancelled = expectation(description: "Synthetic transport cancelled")
        let client = DecisionsClient { _ in
            started.fulfill()
            do { try await Task.sleep(for: .seconds(10)) } catch {
                cancelled.fulfill()
                throw error
            }
            throw DecisionsClientError.invalidResponse
        }
        let task = Task { try await client.choose(input: "Synthetic text", question: question) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    private func client(response: String? = nil, status: Int = 200) -> DecisionsClient {
        let data = Data((response ?? realShape).utf8)
        return DecisionsClient { _ in DecisionsHTTPResponse(data: data, statusCode: status) }
    }

    private func assertFailure(
        _ expected: DecisionsClientError, client: DecisionsClient, input: String = "Synthetic text",
        question: DecisionChoiceQuestion? = nil, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await client.choose(input: input, question: question ?? self.question)
            XCTFail("Expected failure", file: file, line: line)
        } catch { XCTAssertEqual(error as? DecisionsClientError, expected, file: file, line: line) }
    }
}

private actor DecisionsCallCounter {
    private(set) var count = 0
    func record() { count += 1 }
}
