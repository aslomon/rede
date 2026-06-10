import AVFoundation
import Foundation
import OSLog

private let silenceTrimmerLogger = Logger(
  subsystem: "app.rede.mac", category: "SilenceTrimmer")

/// Cuts long speech pauses out of a finished recording so the audio handed to transcription is
/// shorter — faster/cheaper online uploads, less dead air for Whisper to hallucinate into. Fully
/// on-device: it reads the LOCAL recording, finds runs of near-silence, and re-exports only the kept
/// segments to a new temp file. No audio ever leaves the Mac and nothing new is sent anywhere.
///
/// Conservative on purpose: each kept segment is padded so quiet word onsets/tails are never clipped,
/// and EVERY failure path (unreadable audio, nothing worth removing, export error) returns `nil` so
/// the caller transcribes the untouched original. Trimming is best-effort polish, never lossy.
enum SilenceTrimmer {
  struct Parameters: Sendable {
    /// Analysis window length. Short enough to localize pauses, long enough to smooth noise.
    var windowSeconds: Double = 0.05
    /// Linear RMS amplitude (0...1) at/below which a window counts as silence (~ -36 dBFS).
    var silenceThreshold: Float = 0.016
    /// Only pauses LONGER than this are cut; shorter gaps (natural speech rhythm) stay untouched.
    var minSilenceSeconds: Double = 0.7
    /// Speech kept on each side of a cut so word onsets/tails survive the trim.
    var keepPaddingSeconds: Double = 0.18
    /// Don't bother re-exporting unless at least this much audio would actually be removed.
    var minRemovedSeconds: Double = 0.5
    /// Never emit a trimmed file shorter than this — guards against an over-aggressive cut.
    var minKeptSeconds: Double = 0.3

    static let `default` = Parameters()
  }

  // MARK: - Pure core (unit-tested in isolation, no audio I/O)

  /// Given per-window RMS amplitudes, returns the time ranges (seconds) to KEEP after removing
  /// pauses longer than `minSilenceSeconds`. Deterministic. Returns a single full-length range when
  /// there is no speech at all (let downstream quality checks decide), and an empty array for empty
  /// input. Kept segments are padded by `keepPaddingSeconds` and merged where they overlap.
  static func keptRanges(
    windowAmplitudes: [Float],
    windowSeconds: Double,
    parameters: Parameters = .default
  ) -> [Range<Double>] {
    let windowCount = windowAmplitudes.count
    guard windowCount > 0, windowSeconds > 0 else { return [] }
    let totalDuration = Double(windowCount) * windowSeconds

    let isSpeech = windowAmplitudes.map { $0 > parameters.silenceThreshold }
    guard isSpeech.contains(true) else { return [0..<totalDuration] }

    // Contiguous runs of speech windows, as half-open [start, end) index ranges.
    var runs: [(start: Int, end: Int)] = []
    var index = 0
    while index < windowCount {
      guard isSpeech[index] else {
        index += 1
        continue
      }
      var runEnd = index
      while runEnd < windowCount, isSpeech[runEnd] { runEnd += 1 }
      runs.append((index, runEnd))
      index = runEnd
    }

    // Merge runs separated by a gap shorter than the minimum cut length: those short pauses are
    // part of normal speech and must be preserved, not removed.
    let minSilenceWindows = max(1, Int((parameters.minSilenceSeconds / windowSeconds).rounded(.up)))
    var mergedRuns: [(start: Int, end: Int)] = []
    for run in runs {
      if let last = mergedRuns.last, run.start - last.end < minSilenceWindows {
        mergedRuns[mergedRuns.count - 1] = (last.start, run.end)
      } else {
        mergedRuns.append(run)
      }
    }

    // Convert to padded time ranges, then merge any that overlap after padding.
    let padding = parameters.keepPaddingSeconds
    let padded = mergedRuns.map { run -> Range<Double> in
      let lower = max(0, Double(run.start) * windowSeconds - padding)
      let upper = min(totalDuration, Double(run.end) * windowSeconds + padding)
      return lower..<upper
    }

    var result: [Range<Double>] = []
    for range in padded.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      if let last = result.last, range.lowerBound <= last.upperBound {
        result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        result.append(range)
      }
    }
    return result
  }

  /// Total seconds covered by `ranges`.
  static func keptDuration(_ ranges: [Range<Double>]) -> Double {
    ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
  }

  // MARK: - AVFoundation entry point

  /// Returns a NEW temp file containing only the kept (non-pause) audio, or `nil` to signal the
  /// caller should transcribe the original untouched — used both on any error and when there is too
  /// little to gain. The caller owns the returned file and must delete it after use.
  static func trimmedAudio(at url: URL, parameters: Parameters = .default) async -> URL? {
    do {
      let asset = AVURLAsset(url: url)
      guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }

      let sampleRate = try await sourceSampleRate(of: track)
      guard sampleRate > 0 else { return nil }

      let amplitudes = try readWindowAmplitudes(
        asset: asset, track: track, sampleRate: sampleRate, windowSeconds: parameters.windowSeconds)
      guard !amplitudes.isEmpty else { return nil }

      let ranges = keptRanges(
        windowAmplitudes: amplitudes, windowSeconds: parameters.windowSeconds,
        parameters: parameters)
      let total = Double(amplitudes.count) * parameters.windowSeconds
      let kept = keptDuration(ranges)

      // Skip the re-export when it isn't worth it: nothing meaningful removed, or the cut would
      // leave too little audio (most likely a misdetection). Either way → use the original.
      guard
        total - kept >= parameters.minRemovedSeconds,
        kept >= parameters.minKeptSeconds
      else { return nil }

      let trimmed = try await export(asset: asset, ranges: ranges)
      silenceTrimmerLogger.info(
        "Silence-trimmed audio: \(String(format: "%.1f", total))s → \(String(format: "%.1f", kept))s"
      )
      return trimmed
    } catch {
      silenceTrimmerLogger.error(
        "Silence trim failed, using original audio: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  // MARK: - Private helpers

  private static func sourceSampleRate(of track: AVAssetTrack) async throws -> Double {
    let formatDescriptions = try await track.load(.formatDescriptions)
    guard
      let formatDescription = formatDescriptions.first,
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
    else { return 0 }
    return asbd.mSampleRate
  }

  /// Streams the track as mono Float32 PCM and reduces it to one RMS amplitude per analysis window.
  private static func readWindowAmplitudes(
    asset: AVAsset, track: AVAssetTrack, sampleRate: Double, windowSeconds: Double
  ) throws -> [Float] {
    let reader = try AVAssetReader(asset: asset)
    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
      AVNumberOfChannelsKey: 1,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return [] }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? trimError }

    let windowSamples = max(1, Int((sampleRate * windowSeconds).rounded()))
    var amplitudes: [Float] = []
    var sumSquares = 0.0
    var sampleCount = 0

    while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
      defer { CMSampleBufferInvalidate(sampleBuffer) }
      guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

      let byteLength = CMBlockBufferGetDataLength(blockBuffer)
      guard byteLength > 0 else { continue }
      var dataPointer: UnsafeMutablePointer<Int8>?
      guard
        CMBlockBufferGetDataPointer(
          blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil,
          dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
        let dataPointer
      else { continue }

      let floatCount = byteLength / MemoryLayout<Float>.size
      dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
        for k in 0..<floatCount {
          let value = Double(floats[k])
          sumSquares += value * value
          sampleCount += 1
          if sampleCount >= windowSamples {
            amplitudes.append(Float((sumSquares / Double(sampleCount)).squareRoot()))
            sumSquares = 0
            sampleCount = 0
          }
        }
      }
    }

    if sampleCount > 0 {
      amplitudes.append(Float((sumSquares / Double(sampleCount)).squareRoot()))
    }
    if reader.status == .failed { throw reader.error ?? trimError }
    return amplitudes
  }

  /// Re-stitches the kept ranges from the ORIGINAL compressed track into a new AAC/m4a temp file,
  /// preserving source quality (analysis used PCM; the export does not).
  private static func export(asset: AVAsset, ranges: [Range<Double>]) async throws -> URL? {
    let composition = AVMutableComposition()
    guard
      let compositionTrack = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
      let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first
    else { return nil }

    let timescale: CMTimeScale = 600
    var cursor = CMTime.zero
    for range in ranges {
      let start = CMTime(seconds: range.lowerBound, preferredTimescale: timescale)
      let duration = CMTime(
        seconds: range.upperBound - range.lowerBound, preferredTimescale: timescale)
      guard duration.seconds > 0 else { continue }
      try compositionTrack.insertTimeRange(
        CMTimeRange(start: start, duration: duration), of: sourceTrack, at: cursor)
      cursor = cursor + duration
    }
    guard cursor.seconds > 0 else { return nil }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("rede-trimmed-\(UUID().uuidString).m4a")
    guard
      let exportSession = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetAppleM4A)
    else { return nil }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .m4a

    await withCheckedContinuation { continuation in
      exportSession.exportAsynchronously { continuation.resume() }
    }

    guard exportSession.status == .completed else {
      try? FileManager.default.removeItem(at: outputURL)
      throw exportSession.error ?? trimError
    }
    return outputURL
  }

  private static var trimError: NSError {
    NSError(
      domain: "app.rede.mac.SilenceTrimmer", code: -1,
      userInfo: [NSLocalizedDescriptionKey: "Audio konnte nicht gekürzt werden."])
  }
}
