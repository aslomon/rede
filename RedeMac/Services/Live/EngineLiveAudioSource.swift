import AVFoundation

@MainActor final class EngineLiveAudioSource: LiveAudioSource {
    private var engine: AVAudioEngine?
    private var worker: LiveAudioWorker?
    private let configurationObserver = LiveAudioConfigurationObserver()

    func start() throws -> AsyncThrowingStream<LiveAudioChunk, Error> {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw LiveFailure.captureFailed }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let worker = try LiveAudioWorker(format: format)
        let stream = AsyncThrowingStream<LiveAudioChunk, Error>(bufferingPolicy: .bufferingOldest(80)) {
            worker.continuation = $0
        }
        configurationObserver.start(object: engine) { worker.fail($0) }
        input.installTap(onBus: 0, bufferSize: 2400, format: format) { buffer, _ in worker.accept(buffer) }
        do { engine.prepare(); try engine.start() } catch {
            configurationObserver.stop()
            input.removeTap(onBus: 0)
            worker.finish()
            throw LiveFailure.captureFailed
        }
        self.engine = engine
        self.worker = worker
        return stream
    }

    func stop() {
        configurationObserver.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        worker?.finish()
        worker = nil
    }
}

private final class LiveAudioWorker: @unchecked Sendable {
    var continuation: AsyncThrowingStream<LiveAudioChunk, Error>.Continuation?
    private let queue = DispatchQueue(label: "app.rede.live-pcm")
    private let lock = NSLock()
    private var pendingFrames = 0
    private var stopped = false
    private let sampleRate: Double
    private let converter: LivePCMConverter
    private var pending = Data()

    init(format: AVAudioFormat) throws {
        converter = try LivePCMConverter(inputFormat: format)
        sampleRate = format.sampleRate
    }

    func accept(_ buffer: AVAudioPCMBuffer) {
        let state = lock.withLock { () -> Int in
            if stopped { return 0 }
            guard Double(pendingFrames) / sampleRate < 8 else { return -1 }
            pendingFrames += Int(buffer.frameLength)
            return 1
        }
        guard state != 0 else { return }
        guard state == 1,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            continuation?.finish(throwing: LiveFailure.captureFailed); return
        }
        copy.frameLength = buffer.frameLength
        let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in from.indices {
            guard let source = from[index].mData, let target = destination[index].mData else { continue }
            memcpy(target, source, Int(from[index].mDataByteSize))
        }
        queue.async { [self] in
            defer { lock.withLock { pendingFrames -= Int(copy.frameLength) } }
            do { pending.append(try converter.convert(copy)); emitChunks(flush: false) } catch {
                continuation?.finish(throwing: LiveFailure.captureFailed)
            }
        }
    }

    func fail(_ failure: LiveFailure) {
        lock.withLock { stopped = true }
        continuation?.finish(throwing: failure)
    }

    func finish() {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !stopped else { return false }; stopped = true; return true
        }
        guard shouldFinish else { return }
        queue.async { [self] in
            do {
                pending.append(try converter.convert(nil))
                emitChunks(flush: true)
                continuation?.finish()
            } catch { continuation?.finish(throwing: LiveFailure.captureFailed) }
        }
    }

    private func emitChunks(flush: Bool) {
        while pending.count >= 4800 || (flush && !pending.isEmpty) {
            let data = Data(pending.prefix(4800))
            pending.removeFirst(data.count)
            if case .dropped = continuation?.yield(LiveAudioChunk(pcm16: data, rms: LivePCMConverter.rms(data))) {
                continuation?.finish(throwing: LiveFailure.captureFailed)
                return
            }
        }
    }
}
