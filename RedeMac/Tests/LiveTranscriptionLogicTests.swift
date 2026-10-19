import XCTest

@testable import Rede

final class LiveTranscriptionLogicTests: XCTestCase {
    func testDeltasBeforeCommitAreVisibleAndFinalReplacesPartial() {
        var assembler = LiveTranscriptAssembler()
        assembler.delta(itemID: "a", text: "Montag")
        XCTAssertEqual(assembler.snapshot.provisionalText, "Montag")
        assembler.committed(itemID: "a", previousItemID: nil)
        assembler.completed(itemID: "a", transcript: "Mittwoch.")
        assembler.delta(itemID: "a", text: " stale")
        XCTAssertEqual(assembler.snapshot.stableText, "Mittwoch.")
        XCTAssertTrue(assembler.isComplete)
    }

    func testPredecessorOrderAndStablePrefixSurviveOutOfOrderFinals() {
        var assembler = LiveTranscriptAssembler()
        assembler.delta(itemID: "b", text: "Second")
        assembler.delta(itemID: "a", text: "First")
        assembler.committed(itemID: "b", previousItemID: "a")
        assembler.committed(itemID: "a", previousItemID: nil)
        assembler.completed(itemID: "b", transcript: "Second.")
        XCTAssertEqual(assembler.snapshot.stableText, "")
        XCTAssertEqual(assembler.snapshot.provisionalText, "First Second.")
        assembler.completed(itemID: "a", transcript: "First.")
        XCTAssertEqual(assembler.snapshot.text, "First. Second.")
        XCTAssertEqual(assembler.completedItemCount, 2)
    }

    func testEmptyCompletedTurnsAreSkippedAndOpenTurnStaysProvisional() {
        var assembler = LiveTranscriptAssembler()
        assembler.committed(itemID: "a", previousItemID: nil)
        assembler.completed(itemID: "a", transcript: "")
        assembler.delta(itemID: "b", text: "Tail")
        XCTAssertEqual(assembler.snapshot.text, "Tail")
        XCTAssertFalse(assembler.isComplete)
    }

    func testSegmenterCommitsAfterSilenceAndForcesLongTurn() {
        var segmenter = LiveTurnSegmenter()
        XCTAssertFalse(segmenter.append(chunk(seconds: 0.1, rms: 0.1)))
        XCTAssertTrue(segmenter.append(chunk(seconds: 0.8, rms: 0)))
        segmenter.reset()
        XCTAssertTrue(segmenter.append(chunk(seconds: 45, rms: 0.1)))
    }

    func testShortSpeechTailIsPaddedButEmptyBufferIsNeverCommitted() {
        var segmenter = LiveTurnSegmenter()
        XCTAssertNil(segmenter.finalPadding)
        _ = segmenter.append(chunk(seconds: 0.1, rms: 0.1))
        XCTAssertEqual(segmenter.finalPadding?.count, 9600)
    }

    func testCapabilitiesAndAvailabilityDoNotPromiseLocalStreaming() {
        XCTAssertEqual(
            TranscriptionCapabilities.engines.filter { $0.value.streamsPartialText }.map(\.key), ["gpt-live-transcribe"]
        )
        XCTAssertEqual(
            LiveAvailability.resolve(
                featureEnabled: true, secureLocal: true,
                backendIsRemote: true, hasAPIKey: true, microphoneAuthorized: true), .unavailable(.secureLocal))
    }

    private func chunk(seconds: Double, rms: Float) -> LiveAudioChunk {
        LiveAudioChunk(pcm16: Data(repeating: 0, count: Int(seconds * 48_000)), rms: rms)
    }
}
