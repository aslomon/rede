import AVFoundation

/// Queue-confined converter. Microphone and synthetic-buffer paths use the same conversion.
final class LivePCMConverter {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let inputRate: Double

    init(inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000,
                                         channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: output)
        else { throw LiveFailure.captureFailed }
        self.converter = converter
        self.outputFormat = output
        self.inputRate = inputFormat.sampleRate
    }

    func convert(_ input: AVAudioPCMBuffer?) throws -> Data {
        guard let input else {
            var tail = Data()
            for _ in 0..<16 {
                let data = try convertBuffer(nil, capacity: 8192)
                if data.isEmpty { return tail }
                tail.append(data)
            }
            throw LiveFailure.captureFailed
        }
        let capacity = AVAudioFrameCount(max(1024, ceil(Double(input.frameLength) * 24_000 / inputRate) + 256))
        return try convertBuffer(input, capacity: capacity)
    }

    private func convertBuffer(_ input: AVAudioPCMBuffer?, capacity: AVAudioFrameCount) throws -> Data {
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw LiveFailure.captureFailed
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if let input, !supplied { supplied = true; state.pointee = .haveData; return input }
            state.pointee = input == nil ? .endOfStream : .noDataNow
            return nil
        }
        guard error == nil, status != .error else { throw LiveFailure.captureFailed }
        let buffers = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        guard let first = buffers.first, let bytes = first.mData else { return Data() }
        return Data(bytes: bytes, count: Int(output.frameLength) * 2)
    }

    static func rms(_ data: Data) -> Float {
        guard !data.isEmpty else { return 0 }
        var sum: Double = 0
        data.withUnsafeBytes { raw in
            for offset in stride(from: 0, to: data.count - 1, by: 2) {
                let value = raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)
                let sample = Double(Int16(littleEndian: value)) / 32768
                sum += sample * sample
            }
        }
        return Float(sqrt(sum / Double(data.count / 2)))
    }
}
