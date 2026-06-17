import Foundation
import OSLog

enum WorkflowLatencyDiagnostics {
  enum Stage: String {
    case recordingStop = "recording_stop_file_finalization"
    case silenceTrimming = "silence_trimming"
    case transcription = "transcription"
    case transcriptCleanup = "transcript_cleanup_fuzzy_correction"
    case memoryContextRetrieval = "memory_context_retrieval"
    case promptConstruction = "prompt_construction"
    case rewrite = "rewrite"
    case secondVariant = "second_variant_generation"
    case archiveWrite = "archive_write"
    case pasteCopyHandoff = "paste_copy_handoff"
    case total = "total_stop_to_output_handoff"
  }

  private static let logger = Logger(subsystem: "app.rede.mac", category: "WorkflowLatency")

  static func milliseconds(since start: Date, until end: Date = Date()) -> Int {
    Int((end.timeIntervalSince(start) * 1000).rounded())
  }

  static func logStage(
    _ stage: Stage,
    mode: WorkflowType,
    backend: TranscriptionBackend? = nil,
    startedAt start: Date,
    endedAt end: Date = Date()
  ) {
    let backendLabel = backend?.rawValue ?? "none"
    logger.info(
      "stage=\(stage.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) backend=\(backendLabel, privacy: .public) elapsed_ms=\(milliseconds(since: start, until: end), privacy: .public)"
    )
  }

  static func logEvent(_ name: String, mode: WorkflowType, backend: TranscriptionBackend? = nil) {
    let backendLabel = backend?.rawValue ?? "none"
    logger.info(
      "event=\(name, privacy: .public) mode=\(mode.rawValue, privacy: .public) backend=\(backendLabel, privacy: .public)"
    )
  }
}

enum WorkflowAudioPreparation {
  static func audioForTranscription(
    original: URL,
    trimmingEnabled: Bool,
    mode: WorkflowType,
    backend: TranscriptionBackend
  ) async -> URL {
    let startedAt = Date()
    defer {
      WorkflowLatencyDiagnostics.logStage(
        .silenceTrimming,
        mode: mode,
        backend: backend,
        startedAt: startedAt
      )
    }
    guard trimmingEnabled else { return original }
    return await SilenceTrimmer.trimmedAudio(at: original) ?? original
  }
}
