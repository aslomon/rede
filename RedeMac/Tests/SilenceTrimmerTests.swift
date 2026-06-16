import XCTest

@testable import Rede

/// Tests the PURE pause-detection core of `SilenceTrimmer` (no audio I/O). Speech windows use a
/// loud amplitude, silence windows use 0. A 0.1 s window keeps the index→time math easy to read.
final class SilenceTrimmerTests: XCTestCase {

  private let windowSeconds = 0.1
  private let params = SilenceTrimmer.Parameters.default  // minSilence 0.7s, padding 0.18s

  private let loud: Float = 1.0
  private let quiet: Float = 0.0

  private func windows(_ pattern: [(Float, Int)]) -> [Float] {
    pattern.flatMap { Array(repeating: $0.0, count: $0.1) }
  }

  func testEmptyInputYieldsNoRanges() {
    XCTAssertTrue(
      SilenceTrimmer.keptRanges(
        windowAmplitudes: [], windowSeconds: windowSeconds, parameters: params
      )
      .isEmpty)
  }

  func testAllSilenceKeepsFullRange() {
    // No speech anywhere → keep everything and let downstream quality checks decide.
    let amplitudes = windows([(quiet, 10)])  // 1.0 s
    let ranges = SilenceTrimmer.keptRanges(
      windowAmplitudes: amplitudes, windowSeconds: windowSeconds, parameters: params)
    XCTAssertEqual(ranges.count, 1)
    XCTAssertEqual(ranges.first?.lowerBound ?? -1, 0, accuracy: 0.0001)
    XCTAssertEqual(ranges.first?.upperBound ?? -1, 1.0, accuracy: 0.0001)
  }

  func testAllSpeechKeepsSingleFullRange() {
    let amplitudes = windows([(loud, 20)])  // 2.0 s
    let ranges = SilenceTrimmer.keptRanges(
      windowAmplitudes: amplitudes, windowSeconds: windowSeconds, parameters: params)
    XCTAssertEqual(ranges.count, 1)
    XCTAssertEqual(SilenceTrimmer.keptDuration(ranges), 2.0, accuracy: 0.0001)
  }

  func testLongPauseIsCutIntoTwoRanges() {
    // 1.0s speech, 1.0s silence (> 0.7s min), 1.0s speech → the middle pause is removed.
    let amplitudes = windows([(loud, 10), (quiet, 10), (loud, 10)])  // 3.0 s
    let ranges = SilenceTrimmer.keptRanges(
      windowAmplitudes: amplitudes, windowSeconds: windowSeconds, parameters: params)
    XCTAssertEqual(ranges.count, 2)
    // First block padded only on the trailing edge (leading clamps to 0).
    XCTAssertEqual(ranges[0].lowerBound, 0, accuracy: 0.0001)
    XCTAssertEqual(ranges[0].upperBound, 1.0 + params.keepPaddingSeconds, accuracy: 0.0001)
    // Second block starts 0.18s before the speech resumes and runs to the (clamped) end.
    XCTAssertEqual(ranges[1].lowerBound, 2.0 - params.keepPaddingSeconds, accuracy: 0.0001)
    XCTAssertEqual(ranges[1].upperBound, 3.0, accuracy: 0.0001)
    // Some audio was actually removed.
    XCTAssertLessThan(SilenceTrimmer.keptDuration(ranges), 3.0)
  }

  func testShortPauseIsPreserved() {
    // 0.3s gap is below the 0.7s minimum → the two speech blocks stay merged into one range.
    let amplitudes = windows([(loud, 10), (quiet, 3), (loud, 10)])  // 2.3 s
    let ranges = SilenceTrimmer.keptRanges(
      windowAmplitudes: amplitudes, windowSeconds: windowSeconds, parameters: params)
    XCTAssertEqual(ranges.count, 1)
    XCTAssertEqual(ranges.first?.lowerBound ?? -1, 0, accuracy: 0.0001)
    XCTAssertEqual(ranges.first?.upperBound ?? -1, 2.3, accuracy: 0.0001)
  }

  func testThresholdIsStrictlyAbove() {
    // Amplitudes exactly at the threshold count as silence; just above counts as speech.
    let atThreshold = Array(repeating: params.silenceThreshold, count: 10)
    XCTAssertEqual(
      SilenceTrimmer.keptRanges(
        windowAmplitudes: atThreshold, windowSeconds: windowSeconds, parameters: params),
      [0..<1.0])  // treated as all-silence → full range kept

    let aboveThreshold = Array(repeating: params.silenceThreshold + 0.01, count: 10)
    let speechRanges = SilenceTrimmer.keptRanges(
      windowAmplitudes: aboveThreshold, windowSeconds: windowSeconds, parameters: params)
    XCTAssertEqual(speechRanges.count, 1)
    XCTAssertEqual(SilenceTrimmer.keptDuration(speechRanges), 1.0, accuracy: 0.0001)
  }

  func testLeadingAndTrailingSilenceIsTrimmedWithPadding() {
    // 1.0s silence, 1.0s speech, 1.0s silence → keep only the padded speech in the middle.
    let amplitudes = windows([(quiet, 10), (loud, 10), (quiet, 10)])  // 3.0 s
    let ranges = SilenceTrimmer.keptRanges(
      windowAmplitudes: amplitudes, windowSeconds: windowSeconds, parameters: params)
    XCTAssertEqual(ranges.count, 1)
    XCTAssertEqual(ranges[0].lowerBound, 1.0 - params.keepPaddingSeconds, accuracy: 0.0001)
    XCTAssertEqual(ranges[0].upperBound, 2.0 + params.keepPaddingSeconds, accuracy: 0.0001)
  }
}
