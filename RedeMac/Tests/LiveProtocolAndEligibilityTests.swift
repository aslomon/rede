import XCTest
@testable import Rede

final class LiveProtocolAndEligibilityTests: XCTestCase {
    func testSessionUsesPluralLanguagesNullTurnDetectionAndSanitizedKeywords() throws {
        var configuration = LiveConfiguration()
        configuration.keywords = ["<word>\r\n", "word", "", String(repeating: "a", count: 100)]
        let data = try LiveSessionProtocol.sessionUpdate(configuration)
        let event = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap(event["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")
        XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
        XCTAssertEqual(transcription["languages"] as? [String], ["de"])
        XCTAssertNil(transcription["language"])
        XCTAssertNil(transcription["prompt"])
        XCTAssertTrue(input["turn_detection"] is NSNull)
        XCTAssertEqual(transcription["keywords"] as? [String], ["word", String(repeating: "a", count: 60)])
        configuration.language = "auto"
        let automatic = try XCTUnwrap(String(data: LiveSessionProtocol.sessionUpdate(configuration), encoding: .utf8))
        XCTAssertFalse(automatic.contains("languages"))
        XCTAssertEqual(LiveSessionProtocol.sanitizedKeywords((0..<80).map(String.init)).count, 50)
    }

    func testFailureCategoriesNeverExposeRemoteMessages() {
        XCTAssertEqual(LiveSessionProtocol.failure(URLError(.timedOut)), .timeout)
        XCTAssertEqual(LiveSessionProtocol.failure(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(LiveSessionProtocol.failure(LiveFailure.captureFailed), .captureFailed)
        XCTAssertEqual(LiveSessionProtocol.serverFailure(.init(code: "invalid_api_key", type: nil)), .unauthorized)
        XCTAssertEqual(LiveSessionProtocol.serverFailure(.init(code: "model_not_found", type: nil)), .modelUnavailable)
        XCTAssertEqual(LiveSessionProtocol.serverFailure(nil), .server(code: "unknown"))
    }

    func testEligibilityRequiresEveryGateAndSecureLocalWins() {
        for disabled in 0..<6 {
            let value = PurposeRoutingEligibility.resolve(
                masterEnabled: disabled != 0, modeAutomatic: disabled != 1, secureLocal: disabled == 2,
                rewriteIsOpenAI: disabled != 3, kindRewrites: disabled != 4, hasAPIKey: disabled != 5)
            XCTAssertEqual(value, disabled == 2 ? .remoteNotAllowed : disabled == 5 ? .noAPIKey : .notEligible)
        }
        XCTAssertNil(PurposeRoutingEligibility.resolve(masterEnabled: true, modeAutomatic: true, secureLocal: false,
                                                      rewriteIsOpenAI: true, kindRewrites: true, hasAPIKey: true))
        for disabled in 0..<5 {
            let value = LiveAvailability.resolve(featureEnabled: disabled != 0, secureLocal: disabled == 1,
                                                 backendIsRemote: disabled != 2, hasAPIKey: disabled != 3,
                                                 microphoneAuthorized: disabled != 4)
            let reasons: [LiveAvailability.Reason] = [
                .featureOff, .secureLocal, .localBackend, .noAPIKey, .noMicrophone
            ]
            XCTAssertEqual(value, .unavailable(reasons[disabled]))
        }
        XCTAssertEqual(LiveAvailability.resolve(featureEnabled: true, secureLocal: false, backendIsRemote: true,
                                               hasAPIKey: true, microphoneAuthorized: true), .available)
    }
    @MainActor func testSocketRequestBudgetIsSeparateFromControllerHandshakeDeadline() {
        let configuration = URLSessionLiveSocket.makeConfiguration()
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 60)
        XCTAssertEqual(LiveConfiguration().connectionTimeout, .seconds(8))
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
    }

}
