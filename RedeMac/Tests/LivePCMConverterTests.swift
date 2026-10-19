import AVFoundation
import XCTest

@testable import Rede

final class LivePCMConverterTests: XCTestCase {
    func testRealAVAudioConverterResamplesStereoToMonoPCM16() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<48_000 {
            let value = Float(sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.25)
            channels[0][frame] = value
            channels[1][frame] = value
        }
        let converter = try LivePCMConverter(inputFormat: format)
        var data = try converter.convert(buffer)
        data.append(try converter.convert(nil))
        XCTAssertLessThanOrEqual(abs(data.count / 2 - 24_000), 128)
        XCTAssertGreaterThan(LivePCMConverter.rms(data), 0.1)
        XCTAssertLessThan(LivePCMConverter.rms(data), 0.3)
    }
    func testUneven44100HzMonoBuffersKeepFrameCountAndContinuousEnergy() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100,
                                               channels: 1, interleaved: false))
        let converter = try LivePCMConverter(inputFormat: format)
        let sizes = [1024, 2400, 333]
        var output = Data(), offset = 0, index = 0
        while offset < 44_100 {
            let frames = min(sizes[index % sizes.count], 44_100 - offset)
            let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
            input.frameLength = AVAudioFrameCount(frames)
            let channel = try XCTUnwrap(input.floatChannelData?[0])
            for sample in 0..<frames {
                channel[sample] = 0.25 * sin(Float(offset + sample) * 2 * .pi * 440 / 44_100)
            }
            output.append(try converter.convert(input))
            offset += frames
            index += 1
        }
        output.append(try converter.convert(nil))
        XCTAssertEqual(Double(output.count / 2), 24_000, accuracy: 128)
        for start in stride(from: 0, to: output.count - 4799, by: 4800) {
            let energy = LivePCMConverter.rms(output.subdata(in: start..<(start + 4800)))
            XCTAssertGreaterThan(energy, 0.15)
            XCTAssertLessThan(energy, 0.20)
        }
    }

}
