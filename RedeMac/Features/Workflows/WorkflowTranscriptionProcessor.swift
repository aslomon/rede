import Foundation

struct WorkflowTranscriptionResult: Sendable {
  let cleanedText: String
  let transcriptionCompletedAt: Date
}

/// Replaces the transcription step of a run. Production never sets it; tests inject a worker they
/// control (held back, failing, uncooperative) so no microphone, model or network is involved.
typealias WorkflowTranscriptionOverride =
  @Sendable (_ audioURL: URL, _ liveText: String?) async throws -> WorkflowTranscriptionResult

enum WorkflowProcessingError: LocalizedError {
  case noSpeech

  var errorDescription: String? {
    switch self {
    case .noSpeech:
      return TranscriptionQualityService.noSpeechMessage
    }
  }
}

enum WorkflowTranscriptionProcessor {
  /// File transcription (or, when `liveText` is given, the live session's final text) followed by
  /// the existing cleaning. `isRemoteAllowed` is read by the OpenAI client on every attempt.
  /// `liveText` replaces ONLY the transcription call: silence trimming and the audio upload are
  /// skipped, the local recording is still deleted, and cleaning is identical.
  static func transcribeAndClean(
    originalAudioURL: URL,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    vocabularyHints: [String],
    language: String,
    localModelName: String,
    dictionary: DictationDictionary,
    fuzzyTerms: [String],
    silenceTrimmingEnabled: Bool,
    isRemoteAllowed: @escaping @Sendable () -> Bool,
    liveText: String? = nil
  ) async throws -> WorkflowTranscriptionResult {
    if let liveText {
      defer { try? FileManager.default.removeItem(at: originalAudioURL) }
      let cleaned = clean(
        liveText, mode: mode, backend: backend, dictionary: dictionary, fuzzyTerms: fuzzyTerms)
      return WorkflowTranscriptionResult(
        cleanedText: cleaned, transcriptionCompletedAt: Date())
    }
    let audioURL = await WorkflowAudioPreparation.audioForTranscription(
      original: originalAudioURL,
      trimmingEnabled: silenceTrimmingEnabled,
      mode: mode,
      backend: backend
    )
    defer {
      try? FileManager.default.removeItem(at: originalAudioURL)
      if audioURL != originalAudioURL { try? FileManager.default.removeItem(at: audioURL) }
    }

    let transcriptionStartedAt = Date()
    let text: String
    switch backend {
    case .remote:
      text = try await TranscriptionService.transcribe(
        audioURL: audioURL,
        customTerms: vocabularyHints,
        language: language,
        isRemoteAllowed: isRemoteAllowed
      )
    case .local:
      text = try await LocalTranscriptionService.shared.transcribe(
        audioURL: audioURL,
        language: language,
        modelName: localModelName,
        customTerms: vocabularyHints
      )
    }
    let transcriptionCompletedAt = Date()
    WorkflowLatencyDiagnostics.logStage(
      .transcription,
      mode: mode,
      backend: backend,
      startedAt: transcriptionStartedAt,
      endedAt: transcriptionCompletedAt
    )
    let cleaned = clean(
      text, mode: mode, backend: backend, dictionary: dictionary, fuzzyTerms: fuzzyTerms)
    return WorkflowTranscriptionResult(
      cleanedText: cleaned, transcriptionCompletedAt: transcriptionCompletedAt)
  }

  /// The clean-only step: quality cleanup, dictionary, fuzzy correction. Shared by the file path
  /// and the live path so both produce identical text for identical input.
  static func clean(
    _ text: String,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    dictionary: DictationDictionary,
    fuzzyTerms: [String]
  ) -> String {
    let cleanupStartedAt = Date()
    let cleaned = FuzzyTermCorrector.correct(
      DictationPostProcessor.process(
        TranscriptionQualityService.cleanedTranscript(text), dictionary: dictionary),
      terms: fuzzyTerms)
    WorkflowLatencyDiagnostics.logStage(
      .transcriptCleanup,
      mode: mode,
      backend: backend,
      startedAt: cleanupStartedAt
    )
    return cleaned
  }
}
