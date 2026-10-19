import XCTest

@testable import Rede

@MainActor final class LiveTranscriptionControllerTests: XCTestCase {
    func testGateHasZeroSocketAndAudioCalls() async {
        let source = TestLiveAudioSource()
        let socket = TestLiveSocket()
        let controller = make(source, socket, allowed: false)
        controller.begin(LiveConfiguration())
        let result = await controller.finish()
        XCTAssertEqual(result, .unusable(.remoteNotAllowed))
        XCTAssertEqual(source.starts, 0)
        XCTAssertEqual(socket.connections, 0)
    }

    func testLiveDeltaBeforeCommitAndAuthoritativeFinal() async {
        let source = TestLiveAudioSource()
        let socket = TestLiveSocket()
        let controller = make(source, socket)
        controller.begin(LiveConfiguration())
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.1)
        await wait { !controller.snapshot.text.isEmpty }
        XCTAssertEqual(controller.snapshot.text, "Partial")
        guard case .transcript(let text, let stats) = await controller.finish() else {
            return XCTFail("Expected complete live result")
        }
        XCTAssertEqual(text, "Authoritative final.")
        XCTAssertEqual(stats.localCommitCount, 1)
        XCTAssertGreaterThanOrEqual(stats.sentAudioSeconds, 0.3)
        XCTAssertGreaterThan(socket.closes, 0)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.phase, .finished)
        let repeated = await controller.finish()
        XCTAssertEqual(repeated, .transcript(text, stats))
    }

    func testCancelIsTerminalAndLateEventsAreIgnored() async {
        let source = TestLiveAudioSource()
        let socket = TestLiveSocket()
        let controller = make(source, socket)
        controller.begin(LiveConfiguration())
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.1)
        controller.cancel()
        socket.emit([
            "type": "conversation.item.input_audio_transcription.delta", "item_id": "stale", "delta": "PRIVATE_STALE"
        ])
        let result = await controller.finish()
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(controller.snapshot.text, "")
    }

    func testFinalTimeoutFallsBackAndFinishIsIdempotent() async {
        let source = TestLiveAudioSource()
        let socket = TestLiveSocket()
        socket.completes = false
        let controller = make(source, socket)
        var configuration = LiveConfiguration()
        configuration.finalizationTimeout = .milliseconds(40)
        controller.begin(configuration)
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.4)
        let first = await controller.finish()
        let second = await controller.finish()
        XCTAssertEqual(first, .unusable(.timeout))
        XCTAssertEqual(first, second)
    }

    func testHandshakeBufferIsEightSecondsRatherThanFiveSecondOutboundBudget() async {
        let source = TestLiveAudioSource()
        let socket = TestLiveSocket()
        socket.connectionDelay = .milliseconds(50)
        let controller = make(source, socket)
        controller.begin(LiveConfiguration())
        await wait { source.starts == 1 }
        for _ in 0..<60 { source.emit(seconds: 0.1) }
        await wait { controller.phase == .streaming }
        guard case .transcript = await controller.finish() else {
            return XCTFail("Six-second handshake buffer rejected")
        }
    }

    func testSessionUpdatedBeforeSessionCreatedIsProtocolViolation() async {
        let source = TestLiveAudioSource()
        let socket = TestLiveSocket()
        socket.createdFirst = false
        let controller = make(source, socket)
        controller.begin(LiveConfiguration())
        await wait { controller.phase != .connecting }
        XCTAssertEqual(controller.phase, .failed(.protocolViolation))
        controller.cancel()
    }

    func testSlowCredentialLookupDoesNotBlockCaptureAndCancelPreventsConnection() async {
        let source = TestLiveAudioSource()
        let socket = TestLiveSocket()
        let controller = LiveTranscriptionController(
            isRemoteAllowed: { true },
            apiKey: {
                Thread.sleep(forTimeInterval: 0.2)
                return "synthetic-test-key"
            }, audioSource: source, socket: socket)
        let began = Date()
        controller.begin(LiveConfiguration())
        await wait { source.starts == 1 }
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.1)
        source.emit(seconds: 0.1)
        controller.cancel()
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(socket.connections, 0)
        let outcome = await controller.finish()
        XCTAssertEqual(outcome, .cancelled)
    }

    func testTransportCancellationIsTerminalRatherThanFileFallback() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        socket.connectionError = URLError(.cancelled)
        let controller = make(source, socket)
        controller.begin(LiveConfiguration())
        await wait { controller.phase != .connecting }
        let outcome = await controller.finish()
        XCTAssertEqual(outcome, .cancelled)
    }

    func testCaptureFailureRetainsCaptureCategory() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        source.startError = CocoaError(.fileReadUnknown)
        let controller = make(source, socket)
        controller.begin(LiveConfiguration())
        await wait { controller.phase != .connecting }
        let outcome = await controller.finish()
        XCTAssertEqual(outcome, .unusable(.captureFailed))
    }

    func testCanonicalEmptyCommitRejectionThenValidTurnFinishesWithoutAcknowledgementDeficit() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        socket.rejectFirstCommit = true
        let controller = make(source, socket)
        var configuration = LiveConfiguration()
        configuration.finalizationTimeout = .milliseconds(200)
        controller.begin(configuration)
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.1)
        source.emit(seconds: 0.8, rms: 0)
        await wait { socket.commitAttempts == 1 }
        source.emit(seconds: 0.4)
        let began = Date()
        guard case .transcript(let text, let stats) = await controller.finish() else {
            return XCTFail("Rejected empty commit blocked the later valid turn")
        }
        XCTAssertEqual(text, "Authoritative final.")
        XCTAssertEqual(stats.localCommitCount, 2)
        XCTAssertEqual(stats.completedItemCount, 1)
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.15)
    }

    func testUnrelatedEmptyCommitErrorDoesNotReduceValidRequiredAcknowledgements() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        socket.injectUnrelatedEmpty = true
        let controller = make(source, socket)
        controller.begin(LiveConfiguration())
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.4)
        guard case .transcript = await controller.finish() else { return XCTFail("Unrelated error changed the ledger") }
    }

    private func make(
        _ source: TestLiveAudioSource, _ socket: TestLiveSocket,
        allowed: Bool = true
    ) -> LiveTranscriptionController {
        LiveTranscriptionController(
            isRemoteAllowed: { allowed }, apiKey: { "synthetic-test-key" },
            audioSource: source, socket: socket)
    }

    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Synthetic live state timed out")
    }
}
