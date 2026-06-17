import Foundation

struct WorkflowTranscriptionResult: Sendable {
  let cleanedText: String
  let transcriptionCompletedAt: Date
}

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
  static func transcribeAndClean(
    originalAudioURL: URL,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    vocabularyHints: [String],
    language: String,
    localModelName: String,
    dictionary: DictationDictionary,
    fuzzyTerms: [String],
    silenceTrimmingEnabled: Bool
  ) async throws -> WorkflowTranscriptionResult {
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
        language: language
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

    return WorkflowTranscriptionResult(
      cleanedText: cleaned,
      transcriptionCompletedAt: transcriptionCompletedAt
    )
  }
}
