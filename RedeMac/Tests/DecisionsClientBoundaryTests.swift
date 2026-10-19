import XCTest
@testable import Rede

final class DecisionsClientBoundaryTests: XCTestCase {
    private let question = DecisionChoiceQuestion(name: "route", instructions: "Synthetic boundary test.", choices: [
        DecisionChoiceOption(value: .string("email")), DecisionChoiceOption(value: .string("other"))
    ])
    func testUnicodeScalarLimitsRejectOversizedSingleGraphemeBeforeTransport() async {
        let oversized = "a" + String(repeating: "\u{0301}", count: DecisionsClient.maximumQuestionCharacters + 1)
        let invalidQuestions = [
            DecisionChoiceQuestion(name: oversized, instructions: "Question", choices: question.choices),
            DecisionChoiceQuestion(name: "route", instructions: oversized, choices: question.choices),
            DecisionChoiceQuestion(
                name: "route", instructions: "Question",
                choices: [
                    DecisionChoiceOption(value: .string("email"), description: oversized),
                    DecisionChoiceOption(value: .string("other"))
                ])
        ]
        let client = DecisionsClient { _ in
            XCTFail("Oversized Unicode evidence reached transport")
            return DecisionsHTTPResponse(data: Data("{}".utf8), statusCode: 200)
        }
        for invalid in invalidQuestions {
            await assertFailure(.invalidRequest, client: client, question: invalid)
        }
    }

    func testJSONEscapingCannotBypassEncodedRequestByteCeiling() async {
        let escaped = String(repeating: "\u{0001}", count: DecisionsClient.maximumInputBytes / 4)
        let client = DecisionsClient { _ in
            XCTFail("Oversized encoded JSON reached transport")
            return DecisionsHTTPResponse(data: Data("{}".utf8), statusCode: 200)
        }
        await assertFailure(.invalidRequest, client: client, input: escaped)
    }

    func testSecureLocalClientGatePreventsAllTransportCalls() async {
        let client = DecisionsClient(
            isRemoteAllowed: { false },
            transport: { _ in
                XCTFail("Secure-local request reached transport")
                throw DecisionsClientError.networkUnavailable
            })
        do {
            _ = try await client.choose(input: "Synthetic text", question: question)
            XCTFail("Expected gate")
        } catch { XCTAssertTrue(error is RemoteRequestBlocked) }
    }

    private func assertFailure(_ expected: DecisionsClientError, client: DecisionsClient,
                               input: String = "Synthetic text", question: DecisionChoiceQuestion? = nil) async {
        do {
            _ = try await client.choose(input: input, question: question ?? self.question)
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(error as? DecisionsClientError, expected) }
    }
}
