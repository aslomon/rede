import Foundation
import Observation
@MainActor @Observable final class LiveTranscriptionController {
    enum Phase: Equatable, Sendable {
        case idle, connecting, streaming, finishing, finished, failed(LiveFailure), cancelled
    }
    private(set) var phase: Phase = .idle
    private(set) var snapshot = LiveTranscriptSnapshot()
    @ObservationIgnored private let isRemoteAllowed: @Sendable () -> Bool
    @ObservationIgnored private let apiKey: @Sendable () -> String?
    @ObservationIgnored private let audioSource: any LiveAudioSource
    @ObservationIgnored private let socket: any LiveSocketTransport
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var configuration = LiveConfiguration()
    @ObservationIgnored private var assembler = LiveTranscriptAssembler()
    @ObservationIgnored private var segmenter = LiveTurnSegmenter()
    @ObservationIgnored private var stats = LiveStats()
    @ObservationIgnored private var initialQueue: [Outbound] = []
    @ObservationIgnored private var outboundQueue: [Outbound] = []
    @ObservationIgnored private var initialBytes = 0
    @ObservationIgnored private var outboundBytes = 0
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var captureEnded = false
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var senderTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var finishingTask: Task<LiveOutcome, Never>?
    @ObservationIgnored private var outcome: LiveOutcome?
    @ObservationIgnored private var began = Date()
    @ObservationIgnored private var lastPublish = Date.distantPast
    @ObservationIgnored private var commitLedger = LiveCommitLedger()
    @ObservationIgnored private var sessionCreated = false
    @ObservationIgnored private var hasQueuedCommit = false
    private enum Outbound { case audio(Data), commit }

    init(isRemoteAllowed: @escaping @Sendable () -> Bool,
         apiKey: @escaping @Sendable () -> String?,
         audioSource: (any LiveAudioSource)? = nil, socket: (any LiveSocketTransport)? = nil) {
        self.isRemoteAllowed = isRemoteAllowed
        self.apiKey = apiKey
        self.audioSource = audioSource ?? EngineLiveAudioSource()
        self.socket = socket ?? URLSessionLiveSocket()
    }
    func begin(_ configuration: LiveConfiguration) {
        guard phase == .idle else { return }
        guard isRemoteAllowed() else { fail(.remoteNotAllowed); return }
        self.configuration = configuration
        phase = .connecting
        began = Date()
        let run = generation
        captureTask = Task { [weak self] in await self?.capture(run: run) }
        connectionTask = Task { [weak self] in await self?.connect(run: run) }
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: configuration.connectionTimeout)
            guard let self, !Task.isCancelled, generation == run, !ready else { return }
            fail(.timeout)
        }
    }
    func finish() async -> LiveOutcome {
        if Task.isCancelled { cancel(); return .cancelled }
        if let outcome { return outcome }
        if finishingTask == nil {
            let run = generation
            finishingTask = Task { await self.finalize(run: run) }
        }
        let result = await withTaskCancellationHandler {
            await finishingTask!.value
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
        if Task.isCancelled { cancel(); return .cancelled }
        return outcome ?? result
    }
    func cancel() {
        guard phase != .cancelled else { return }
        generation += 1
        outcome = .cancelled
        phase = .cancelled
        snapshot = LiveTranscriptSnapshot()
        cleanup()
    }
}

extension LiveTranscriptionController {
    private func capture(run: Int) async {
        do {
            guard isRemoteAllowed() else { throw LiveFailure.remoteNotAllowed }
            let stream = try audioSource.start()
            if stopRequested { audioSource.stop() }
            for try await chunk in stream {
                guard generation == run, !Task.isCancelled else { return }
                guard chunk.pcm16.count.isMultiple(of: 2), chunk.rms.isFinite else { throw LiveFailure.captureFailed }
                enqueue(chunk)
            }
            if generation == run { captureEnded = true }
        } catch {
            if generation == run { terminate(error, capture: true) }
        }
    }
    private func connect(run: Int) async {
        do {
            guard isRemoteAllowed() else { throw LiveFailure.remoteNotAllowed }
            let key = try await LiveCredentialLoader.load(apiKey, isRemoteAllowed: isRemoteAllowed)
            guard generation == run, !Task.isCancelled else { return }
            guard let key, !key.isEmpty else { throw LiveFailure.unauthorized }
            guard isRemoteAllowed() else { throw LiveFailure.remoteNotAllowed }
            try await socket.connect(apiKey: key)
            while generation == run, !Task.isCancelled {
                let data = try await socket.receive()
                guard generation == run, !Task.isCancelled else { return }
                guard let event = try? JSONDecoder().decode(LiveWireEvent.self, from: data) else {
                    throw LiveFailure.protocolViolation
                }
                try await handle(event)
            }
        } catch {
            if generation == run { terminate(error) }
        }
    }
    private func handle(_ event: LiveWireEvent) async throws {
        guard isRemoteAllowed() else { throw LiveFailure.remoteNotAllowed }
        if event.type.hasPrefix("conversation.item.input_audio_transcription.")
            || event.type == "input_audio_buffer.committed" {
            try applyTranscriptEvent(event)
            publish()
            return
        }
        switch event.type {
        case "session.created":
            guard !sessionCreated else { throw LiveFailure.protocolViolation }
            sessionCreated = true
            try await socket.send(LiveSessionProtocol.sessionUpdate(configuration))
        case "session.updated":
            guard sessionCreated else { throw LiveFailure.protocolViolation }
            ready = true
            deadlineTask?.cancel()
            if !stopRequested { phase = .streaming }
            pump()
        case "error":
            if ["input_audio_buffer_commit_empty", "commit_empty"].contains(event.error?.code ?? "") {
                commitLedger.rejectEmpty(eventID: event.error?.eventID)
            } else { throw LiveSessionProtocol.serverFailure(event.error) }
        default: break
        }
        publish()
    }
    private func applyTranscriptEvent(_ event: LiveWireEvent) throws {
        guard (event.contentIndex ?? 0) == 0 else { throw LiveFailure.protocolViolation }
        switch event.type {
        case "input_audio_buffer.committed":
            guard let id = event.itemID else { throw LiveFailure.protocolViolation }
            commitLedger.acknowledge(itemID: id)
            LiveDiagnostics.checkCommitCount(local: commitLedger.requiredAcknowledgements,
                                             server: commitLedger.receivedAcknowledgements)
            assembler.committed(itemID: id, previousItemID: event.previousItemID)
        case "conversation.item.input_audio_transcription.delta":
            guard let id = event.itemID else { throw LiveFailure.protocolViolation }
            if stats.firstDeltaLatency == nil { stats.firstDeltaLatency = Date().timeIntervalSince(began) }
            assembler.delta(itemID: id, text: event.delta ?? "")
        case "conversation.item.input_audio_transcription.completed":
            guard let id = event.itemID, let text = event.transcript else { throw LiveFailure.protocolViolation }
            assembler.completed(itemID: id, transcript: text)
        case "conversation.item.input_audio_transcription.failed": throw LiveSessionProtocol.serverFailure(event.error)
        default: break
        }
    }
    private func enqueue(_ chunk: LiveAudioChunk) {
        guard !chunk.pcm16.isEmpty else { return }
        if !isRemoteAllowed() { fail(.remoteNotAllowed); return }
        if ready {
            outboundBytes += chunk.pcm16.count
            guard outboundBytes <= 5 * 48_000 else { fail(.network); return }
            outboundQueue.append(.audio(chunk.pcm16))
        } else {
            initialBytes += chunk.pcm16.count
            guard initialBytes <= 8 * 48_000 else { fail(.timeout); return }
            initialQueue.append(.audio(chunk.pcm16))
        }
        if segmenter.append(chunk) { queueCommit() }
        pump()
    }
    private func queueCommit() {
        hasQueuedCommit = true
        if ready { outboundQueue.append(.commit) } else { initialQueue.append(.commit) }
        segmenter.reset()
    }
    private func pump() {
        guard ready, senderTask == nil else { return }
        let run = generation
        senderTask = Task { [weak self] in
            guard let self else { return }
            do {
                while generation == run, let event = nextOutbound() {
                    try Task.checkCancellation()
                    guard isRemoteAllowed() else { throw LiveFailure.remoteNotAllowed }
                    switch event {
                    case .audio(let data):
                        try await socket.send(LiveSessionProtocol.append(data))
                        stats.sentAudioSeconds += Double(data.count) / 48_000
                    case .commit:
                        let eventID = commitLedger.beginAttempt()
                        stats.localCommitCount += 1
                        try await socket.send(LiveSessionProtocol.commit(eventID: eventID))
                    }
                }
            } catch { if generation == run { terminate(error) } }
            if generation == run { senderTask = nil }
        }
    }
    private func nextOutbound() -> Outbound? {
        if !initialQueue.isEmpty {
            let event = initialQueue.removeFirst()
            if case .audio(let data) = event { initialBytes -= data.count }
            return event
        }
        guard !outboundQueue.isEmpty else { return nil }
        let event = outboundQueue.removeFirst()
        if case .audio(let data) = event { outboundBytes -= data.count }
        return event
    }
    private func finalize(run: Int) async -> LiveOutcome {
        guard phase != .idle else { return .unusable(.captureFailed) }
        stopRequested = true
        phase = .finishing
        audioSource.stop()
        let deadline = ContinuousClock.now + configuration.finalizationTimeout
        var tailQueued = false
        while generation == run, !Task.isCancelled, ContinuousClock.now < deadline {
            if !isRemoteAllowed() { fail(.remoteNotAllowed); break }
            if captureEnded && !tailQueued {
                queueFinalTail()
                tailQueued = true
                pump()
            }
            if tailQueued && senderTask == nil && initialQueue.isEmpty && outboundQueue.isEmpty {
                if let result = completedOutcome() { return result }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if Task.isCancelled { cancel(); return .cancelled }
        if let outcome { return outcome }
        fail(.timeout)
        return outcome!
    }
    private func queueFinalTail() {
        guard let padding = segmenter.finalPadding(allowSilenceOnly: !hasQueuedCommit) else { return }
        if !padding.isEmpty { enqueue(LiveAudioChunk(pcm16: padding, rms: 0)) }
        if segmenter.duration > 0 { queueCommit() }
    }
    private func completedOutcome() -> LiveOutcome? {
        guard stats.localCommitCount > 0 else { fail(.protocolViolation); return outcome }
        if commitLedger.allAttemptsRejected { fail(.protocolViolation); return outcome }
        guard commitLedger.isComplete, assembler.isComplete else { return nil }
        let text = assembler.snapshot.text
        guard !text.isEmpty else { fail(.protocolViolation); return outcome }
        snapshot = assembler.snapshot
        stats.completedItemCount = assembler.completedItemCount
        outcome = .transcript(text, stats)
        phase = .finished
        cleanup()
        return outcome
    }
    private func publish() {
        guard snapshotTask == nil else { return }
        let run = generation
        let elapsed = Date().timeIntervalSince(lastPublish)
        if elapsed >= 0.05 { snapshot = assembler.snapshot; lastPublish = Date(); return }
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, generation == run, !Task.isCancelled else { return }
            snapshot = assembler.snapshot
            lastPublish = Date()
            snapshotTask = nil
        }
    }
    private func terminate(_ error: Error, capture: Bool = false) {
        guard outcome == nil else { return }
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
            cancel()
        } else {
            fail(error as? LiveFailure ?? (capture ? .captureFailed : LiveSessionProtocol.failure(error)))
        }
    }
    private func fail(_ failure: LiveFailure) {
        guard outcome == nil else { return }
        generation += 1
        outcome = .unusable(failure)
        phase = .failed(failure)
        cleanup()
    }
    private func cleanup() {
        audioSource.stop()
        socket.close()
        captureTask?.cancel(); connectionTask?.cancel(); senderTask?.cancel()
        deadlineTask?.cancel(); snapshotTask?.cancel()
        initialQueue.removeAll(); outboundQueue.removeAll()
        initialBytes = 0; outboundBytes = 0
    }
}
