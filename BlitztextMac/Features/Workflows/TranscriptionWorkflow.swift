import AppKit
import Foundation
import OSLog
import Observation

private let transcriptionLogger = Logger(subsystem: "app.rede.mac", category: "Transcription")

private func elapsedMilliseconds(since start: Date, until end: Date = Date()) -> Int {
  Int((end.timeIntervalSince(start) * 1000).rounded())
}

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
      recorder.stopRecording()
      guard
        !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration)
      else {
        recorder.discardRecording()
        phase = .error(TranscriptionQualityService.noSpeechMessage)
        return
      }
      transcribe()
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

  private func transcribe() {
    guard let url = recorder.recordingURL else {
      phase = .error("Keine Aufnahme vorhanden.")
      return
    }

    phase = .running(backend == .local ? "wird lokal transkribiert …" : "wird transkribiert …")
    let recordingDuration = recorder.lastRecordingDuration
    let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []
    let requestLanguage = language
    let stopTime = Date()

    transcriptionTask = Task(priority: .userInitiated) {
      // Optionally cut long pauses first; `audioURL` is the original when trimming is off/failed.
      let audioURL = await AudioRecorder.audioForTranscription(original: url)
      defer {
        try? FileManager.default.removeItem(at: url)
        if audioURL != url { try? FileManager.default.removeItem(at: audioURL) }
      }

      let requestStart = Date()
      do {
        let text: String
        switch backend {
        case .remote:
          text = try await TranscriptionService.transcribe(
            audioURL: audioURL,
            customTerms: vocabularyHints,
            language: requestLanguage
          )
        case .local:
          text = try await LocalTranscriptionService.shared.transcribe(
            audioURL: audioURL,
            language: requestLanguage,
            modelName: localModelName,
            customTerms: vocabularyHints
          )
        }
        try Task.checkCancellation()

        let responseReceivedAt = Date()
        let cleaned = FuzzyTermCorrector.correct(
          DictationPostProcessor.process(
            TranscriptionQualityService.cleanedTranscript(text), dictionary: dictionary),
          terms: fuzzyTerms)
        guard
          !TranscriptionQualityService.isLikelyArtifact(
            cleaned, recordingDuration: recordingDuration)
        else {
          transcriptionLogger.info(
            "Transcription rejected short artifact after \(elapsedMilliseconds(since: stopTime)) ms"
          )
          phase = .error(TranscriptionQualityService.noSpeechMessage)
          return
        }

        transcriptionLogger.info(
          "Transcription ready in \(elapsedMilliseconds(since: stopTime, until: responseReceivedAt)) ms (request \(elapsedMilliseconds(since: requestStart, until: responseReceivedAt)) ms)"
        )
        phase = .done(cleaned)
        onRun?(
          ArchiveRunRecord(
            mode: type,
            rawTranscript: cleaned,
            finalText: cleaned,
            backend: backend,
            durationSec: recordingDuration
          )
        )
        onOutput?(cleaned)
      } catch {
        transcriptionLogger.error(
          "Transcription failed after \(elapsedMilliseconds(since: stopTime)) ms: \(error.localizedDescription, privacy: .private)"
        )
        phase = .error(error.localizedDescription)
      }
    }
  }
}
