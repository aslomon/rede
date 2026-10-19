import XCTest
@testable import Rede

@MainActor final class TestLiveAudioSource: LiveAudioSource {
    var starts = 0
    var startError: Error?
    var continuation: AsyncThrowingStream<LiveAudioChunk, Error>.Continuation?
    func start() throws -> AsyncThrowingStream<LiveAudioChunk, Error> {
        starts += 1
        if let startError { throw startError }
        return AsyncThrowingStream { continuation = $0 }
    }
    func stop() { continuation?.finish() }
    func emit(seconds: Double, rms: Float = 0.1) {
        continuation?.yield(LiveAudioChunk(pcm16: Data(repeating: 0, count: Int(seconds * 48_000)), rms: rms))
    }
}

@MainActor final class TestLiveSocket: LiveSocketTransport {
    var connections = 0, closes = 0
    var completes = true, createdFirst = true
    var rejectFirstCommit = false, injectUnrelatedEmpty = false
    var rejectsAllCommits = false
    var commitAttempts = 0
    var connectionError: Error?
    var connectionDelay: Duration = .zero
    private var queue: [Data] = []
    private var waiter: CheckedContinuation<Data, Error>?
    func connect(apiKey: String) async throws {
        connections += 1
        if let connectionError { throw connectionError }
        try await Task.sleep(for: connectionDelay)
        emit(["type": createdFirst ? "session.created" : "session.updated"])
    }
    func send(_ event: Data) async throws {
        let object = try JSONSerialization.jsonObject(with: event) as? [String: Any]
        switch object?["type"] as? String {
        case "session.update": emit(["type": "session.updated"])
        case "input_audio_buffer.append":
            if (rejectFirstCommit && commitAttempts == 0) || rejectsAllCommits { return }
            emit(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a", "delta": "Partial"])
        case "input_audio_buffer.commit":
            commitAttempts += 1
            if (rejectFirstCommit && commitAttempts == 1) || rejectsAllCommits {
                let id = object?["event_id"] as? String ?? "missing-commit-id"
                emit(["type": "error", "error": ["type": "invalid_request_error",
                                                "code": "input_audio_buffer_commit_empty", "event_id": id]])
                return
            }
            if injectUnrelatedEmpty {
                emit(["type": "error", "error": ["code": "commit_empty", "event_id": "unrelated"]])
            }
            emit(["type": "input_audio_buffer.committed", "item_id": "a"])
            if completes {
                emit([
                    "type": "conversation.item.input_audio_transcription.completed", "item_id": "a",
                    "transcript": "Authoritative final."
                ])
            }
        default: break
        }
    }
    func receive() async throws -> Data {
        if !queue.isEmpty { return queue.removeFirst() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    func close() {
        closes += 1
        waiter?.resume(throwing: CancellationError())
        waiter = nil
    }
    func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else {
            return XCTFail("Invalid synthetic event")
        }
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: data)
        } else {
            queue.append(data)
        }
    }
}
