import Foundation

enum TranscriptionQualityService {
  static let minimumRecordingDuration: TimeInterval = 0.3

  /// Shown (as a `.error` phase) when a recording held no usable speech — too short or only an
  /// artifact. BENIGN, not a failure: the earcon gate treats this distinctly from real errors so
  /// eyes-off users don't hear the harsh "broke" tone for a normal silent take. Single source of
  /// truth so the four workflows and the earcon check can never drift apart.
  static let noSpeechMessage = "Keine Aufnahme erkannt."

  static func shouldRejectRecording(duration: TimeInterval) -> Bool {
    duration < minimumRecordingDuration
  }

  static func cleanedTranscript(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool {
    let cleaned = cleanedTranscript(text)
    guard !cleaned.isEmpty else { return true }

    let words = cleaned.split { $0.isWhitespace || $0.isNewline }
    let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

    if letters == 0 {
      return true
    }

    if recordingDuration < 0.55 && (words.count >= 5 || cleaned.count >= 32) {
      return true
    }

    if recordingDuration < 0.8 && cleaned.count >= 56 {
      return true
    }

    return false
  }
}
