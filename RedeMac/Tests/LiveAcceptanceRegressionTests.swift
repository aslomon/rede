import AVFoundation
import XCTest
@testable import Rede

@MainActor final class LiveAcceptanceRegressionTests: XCTestCase {
    func testHardwareConfigurationNotificationFailsOnceAndStopDropsQueuedOldGeneration() async {
        let center = NotificationCenter()
        let observer = LiveAudioConfigurationObserver(center: center)
        let engine = NSObject()
        var failures: [LiveFailure] = []
        observer.start(object: engine) { failures.append($0) }
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        observer.stop()
        observer.start(object: engine) { failures.append($0) }
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(failures, [])
        center.post(name: .AVAudioEngineConfigurationChange, object: NSObject())
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(failures, [.captureFailed])
        observer.stop()
        center.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(failures, [.captureFailed])
    }

    func testSilenceOnlyTailAfterCompletedTurnDoesNotCreateAnotherCommit() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        let controller = make(source, socket)
        controller.begin(configuration)
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.1)
        source.emit(seconds: 0.8, rms: 0)
        await wait { socket.commitAttempts == 1 }
        source.emit(seconds: 0.4, rms: 0)
        guard case .transcript = await controller.finish() else { return XCTFail("Silence tail blocked valid text") }
        XCTAssertEqual(socket.commitAttempts, 1)
    }

    func testFirstQuietTurnRemainsEligibleForOneCommit() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        let controller = make(source, socket)
        controller.begin(configuration)
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.4, rms: 0.001)
        guard case .transcript = await controller.finish() else { return XCTFail("Quiet first turn was discarded") }
        XCTAssertEqual(socket.commitAttempts, 1)
    }

    func testAllRejectedCommitsFailFastInsteadOfWaitingFinalTimeout() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        socket.rejectsAllCommits = true
        let controller = make(source, socket)
        controller.begin(configuration)
        await wait { controller.phase == .streaming }
        source.emit(seconds: 0.4)
        let began = Date()
        let outcome = await controller.finish()
        XCTAssertEqual(outcome, .unusable(.protocolViolation))
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.15)
    }

    func testUnexpectedContentPartFailsClosedBeforePublishingItsText() async {
        let source = TestLiveAudioSource(), socket = TestLiveSocket()
        let controller = make(source, socket)
        controller.begin(configuration)
        await wait { controller.phase == .streaming }
        socket.emit(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a",
                     "content_index": 1, "delta": "Wrong content part"])
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(controller.phase, .failed(.protocolViolation))
        XCTAssertTrue(controller.snapshot.text.isEmpty)
        controller.cancel()
    }

    func testNewCancelledControllersShareOneBlockedNativeCredentialWorker() async {
        let probe = LiveLookupProbe()
        let provider: @Sendable () -> String? = {
            probe.record()
            Thread.sleep(forTimeInterval: 0.3)
            return "synthetic-test-key"
        }
        let first = LiveTranscriptionController(isRemoteAllowed: { true }, apiKey: provider,
                                                audioSource: TestLiveAudioSource(), socket: TestLiveSocket())
        first.begin(configuration)
        await wait { probe.calls == 1 }
        first.cancel()
        var sockets: [TestLiveSocket] = []
        for _ in 0..<12 {
            let socket = TestLiveSocket()
            let controller = LiveTranscriptionController(isRemoteAllowed: { true }, apiKey: provider,
                                                         audioSource: TestLiveAudioSource(), socket: socket)
            controller.begin(configuration)
            try? await Task.sleep(for: .milliseconds(5))
            controller.cancel()
            sockets.append(socket)
        }
        XCTAssertEqual(probe.calls, 1)
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(sockets.allSatisfy { $0.connections == 0 })
    }

    private var configuration: LiveConfiguration {
        var value = LiveConfiguration()
        value.finalizationTimeout = .milliseconds(200)
        return value
    }
    private func make(_ source: TestLiveAudioSource, _ socket: TestLiveSocket) -> LiveTranscriptionController {
        LiveTranscriptionController(isRemoteAllowed: { true }, apiKey: { "synthetic-test-key" },
                                    audioSource: source, socket: socket)
    }
    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Synthetic state timed out")
    }
}

private final class LiveLookupProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func record() { lock.withLock { count += 1 } }
}
