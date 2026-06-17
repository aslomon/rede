import AppKit
import Foundation
import OSLog
import Observation

private let transcriptionLogger = Logger(subsystem: "app.rede.mac", category: "Transcription")

@Observable
@MainActor
final class TranscriptionWorkflow: Workflow {
  let type: WorkflowType
  var phase: WorkflowPhase = .idle {
    didSet { onPhaseChange?(phase) }
  }
  var onOutput: WorkflowOutputHandler?
  var onPhaseChange: WorkflowPhaseChangeHandler?
  var onRun: WorkflowRunHandler?

  private let recorder = AudioRecorder()
  private let customTerms: [String]
  private let dictionary: DictationDictionary
  /// Canonical KNOWN terms used to fuzzy-correct near-miss spellings AFTER the dictionary. Empty
  /// (the default, or when the feature is off) → the corrector is a no-op.
  private let fuzzyTerms: [String]
  private let language: String
  private let backend: TranscriptionBackend
  private let localModelName: String
  private var transcriptionTask: Task<Void, Never>?

  init(
    type: WorkflowType = .transcription,
    customTerms: [String] = [],
    dictionary: DictationDictionary = DictationDictionary(),
    fuzzyTerms: [String] = [],
    language: String = "de",
    backend: TranscriptionBackend = .remote,
    localModelName: String = LocalTranscriptionService.recommendedFastModelName
  ) {
    self.type = type
    self.customTerms = customTerms
    self.dictionary = dictionary
    self.fuzzyTerms = fuzzyTerms
    self.language = language
    self.backend = backend
    self.localModelName = localModelName
  }

  func start() {
    // Start the recorder FIRST so `recorder.isRecording` is true before `phase = .running`
    // emits onPhaseChange — otherwise AppState reads isRecording==false and shows the menu-bar
    // status (and the floating pill) as ".processing" instead of ".recording".
    recorder.startRecording()

    if let error = recorder.errorMessage {
      phase = .error(error)
      return
    }
    // Safety cap: if the recording runs past the max duration, stop+transcribe what we have
    // instead of letting it grow unbounded. `stop()` runs the normal transcription path.
    recorder.onMaxDurationReached = { [weak self] in self?.stop() }
    phase = .running("aufnahme läuft …")
  }

  func stop() {
    if recorder.isRecording {
      let stopStartedAt = Date()
      recorder.stopRecording()
      WorkflowLatencyDiagnostics.logStage(
        .recordingStop,
        mode: type,
        backend: backend,
        startedAt: stopStartedAt
      )
      guard
        !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration)
      else {
        recorder.discardRecording()
        phase = .error(TranscriptionQualityService.noSpeechMessage)
        return
      }
      transcribe(totalStartedAt: stopStartedAt)
    } else {
      transcriptionTask?.cancel()
      phase = .idle
    }
  }

  func reset() {
    transcriptionTask?.cancel()
    if recorder.isRecording {
      recorder.stopRecording()
    }
    recorder.discardRecording()
    phase = .idle
  }

  var isRecording: Bool { recorder.isRecording }
  var audioLevel: Float { recorder.audioLevel }
  var didTruncateAtMaxDuration: Bool { recorder.didStopAtMaxDuration }

  private func transcribe(totalStartedAt: Date) {
    guard let url = recorder.recordingURL else {
      phase = .error("Keine Aufnahme vorhanden.")
      return
    }

    phase = .running(backend == .local ? "wird lokal transkribiert …" : "wird transkribiert …")
    let recordingDuration = recorder.lastRecordingDuration
    let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []
    let requestLanguage = language
    let shouldTrimSilence = AudioRecorder.silenceTrimmingEnabled
    let mode = type
    let transcriptionBackend = backend
    let selectedLocalModelName = localModelName
    let dictationDictionary = dictionary
    let correctionTerms = fuzzyTerms

    transcriptionTask = Task(priority: .userInitiated) {
      let requestStart = Date()
      let worker = Task.detached(priority: .userInitiated) {
        try await WorkflowTranscriptionProcessor.transcribeAndClean(
          originalAudioURL: url,
          mode: mode,
          backend: transcriptionBackend,
          vocabularyHints: vocabularyHints,
          language: requestLanguage,
          localModelName: selectedLocalModelName,
          dictionary: dictationDictionary,
          fuzzyTerms: correctionTerms,
          silenceTrimmingEnabled: shouldTrimSilence
        )
      }
      do {
        let processed = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        try Task.checkCancellation()

        guard
          !TranscriptionQualityService.isLikelyArtifact(
            processed.cleanedText, recordingDuration: recordingDuration)
        else {
          transcriptionLogger.info(
            "Transcription rejected short artifact after \(WorkflowLatencyDiagnostics.milliseconds(since: totalStartedAt), privacy: .public) ms"
          )
          phase = .error(TranscriptionQualityService.noSpeechMessage)
          return
        }

        transcriptionLogger.info(
          "Transcription ready in \(WorkflowLatencyDiagnostics.milliseconds(since: totalStartedAt, until: processed.transcriptionCompletedAt), privacy: .public) ms (request \(WorkflowLatencyDiagnostics.milliseconds(since: requestStart, until: processed.transcriptionCompletedAt), privacy: .public) ms)"
        )
        phase = .done(processed.cleanedText)
        onRun?(
          ArchiveRunRecord(
            mode: mode,
            rawTranscript: processed.cleanedText,
            finalText: processed.cleanedText,
            backend: transcriptionBackend,
            durationSec: recordingDuration
          )
        )
        onOutput?(processed.cleanedText)
        WorkflowLatencyDiagnostics.logStage(
          .total,
          mode: mode,
          backend: transcriptionBackend,
          startedAt: totalStartedAt
        )
      } catch {
        transcriptionLogger.error(
          "Transcription failed after \(WorkflowLatencyDiagnostics.milliseconds(since: totalStartedAt), privacy: .public) ms: \(error.localizedDescription, privacy: .private)"
        )
        phase = .error(error.localizedDescription)
      }
    }
  }
}
