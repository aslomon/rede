import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class DampfAblassenWorkflow: Workflow {
  let type = WorkflowType.dampfAblassen
  var phase: WorkflowPhase = .idle {
    didSet { onPhaseChange?(phase) }
  }
  var onOutput: WorkflowOutputHandler?
  var onPhaseChange: WorkflowPhaseChangeHandler?
  var onRun: WorkflowRunHandler?
  var onVariants: WorkflowVariantChoiceHandler?
  /// Fired once per run with the model-fallback note (`nil` when the chosen model ran). See B6.
  var onRewriteFallback: WorkflowRewriteFallbackHandler?

  private let recorder = AudioRecorder()
  private let rewrite: RewriteConfig
  private let provider: any RewriteProvider
  private let customTerms: [String]
  /// Terms for the REWRITE prompt — natural (most-important-first) order, no Whisper cap.
  /// Defaults to `customTerms` so callers that don't split keep the previous behavior.
  private let rewriteTerms: [String]
  private let dictionary: DictationDictionary
  /// Canonical KNOWN terms used to fuzzy-correct near-miss spellings AFTER the dictionary. Empty
  /// (the default, or when the feature is off) → the corrector is a no-op.
  private let fuzzyTerms: [String]
  private let language: String
  private let backend: TranscriptionBackend
  private let localModelName: String
  private let automaticContext: AutomaticRewriteContext?
  private let memoryContext: MemoryContext?
  private let userIdentity: UserIdentityContext?
  private var processingTask: Task<Void, Never>?

  init(
    rewrite: RewriteConfig,
    provider: any RewriteProvider,
    customTerms: [String] = [],
    rewriteTerms: [String]? = nil,
    dictionary: DictationDictionary = DictationDictionary(),
    fuzzyTerms: [String] = [],
    language: String = "de",
    backend: TranscriptionBackend = .remote,
    localModelName: String = LocalTranscriptionService.recommendedFastModelName,
    automaticContext: AutomaticRewriteContext? = nil,
    memoryContext: MemoryContext? = nil,
    userIdentity: UserIdentityContext? = nil
  ) {
    self.rewrite = rewrite
    self.provider = provider
    self.customTerms = customTerms
    self.rewriteTerms = rewriteTerms ?? customTerms
    self.dictionary = dictionary
    self.fuzzyTerms = fuzzyTerms
    self.language = language
    self.backend = backend
    self.localModelName = localModelName
    self.automaticContext = automaticContext
    self.memoryContext = memoryContext
    self.userIdentity = userIdentity
  }

  // MARK: - Recording State

  var isRecording: Bool { recorder.isRecording }
  var audioLevel: Float { recorder.audioLevel }
  var didTruncateAtMaxDuration: Bool { recorder.didStopAtMaxDuration }

  // MARK: - Workflow Protocol

  func start() {
    // Recorder first so isRecording is true before .running fires (see TranscriptionWorkflow).
    recorder.startRecording()

    if let error = recorder.errorMessage {
      phase = .error(error)
      return
    }
    // Safety cap: if the recording runs past the max duration, stop+process what we have.
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
      processRecording(totalStartedAt: stopStartedAt)
    } else {
      processingTask?.cancel()
      phase = .idle
    }
  }

  func reset() {
    processingTask?.cancel()
    if recorder.isRecording {
      recorder.stopRecording()
    }
    recorder.discardRecording()
    phase = .idle
  }

  // MARK: - Two-Phase Processing: Transcribe -> Rewrite

  private func processRecording(totalStartedAt: Date) {
    guard let url = recorder.recordingURL else {
      phase = .error("Keine Aufnahme vorhanden.")
      return
    }

    phase = .running("wird transkribiert …")
    let recordingDuration = recorder.lastRecordingDuration
    let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []
    let mode = type
    let transcriptionBackend = backend
    let requestLanguage = language
    let selectedLocalModelName = localModelName
    let dictationDictionary = dictionary
    let correctionTerms = fuzzyTerms
    let shouldTrimSilence = AudioRecorder.silenceTrimmingEnabled
    let rewriteConfig = rewrite
    let rewriteProvider = provider
    let rewritePromptTerms = rewriteTerms
    let automaticRewriteContext = automaticContext
    let personalMemoryContext = memoryContext
    let identityContext = userIdentity

    processingTask = Task(priority: .userInitiated) {
      let transcriptionWorker = Task.detached(priority: .userInitiated) {
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
        let transcription = try await withTaskCancellationHandler {
          try await transcriptionWorker.value
        } onCancel: {
          transcriptionWorker.cancel()
        }
        guard
          !TranscriptionQualityService.isLikelyArtifact(
            transcription.cleanedText, recordingDuration: recordingDuration)
        else {
          phase = .error(TranscriptionQualityService.noSpeechMessage)
          return
        }

        if Task.isCancelled { return }

        phase = .running("wird umformuliert …")
        let rewriteWorker = Task.detached(priority: .userInitiated) {
          try await WorkflowRewriteProcessor.dampfAblassenResult(
            cleanedRawText: transcription.cleanedText,
            recordingDuration: recordingDuration,
            mode: mode,
            backend: transcriptionBackend,
            rewrite: rewriteConfig,
            provider: rewriteProvider,
            rewriteTerms: rewritePromptTerms,
            automaticContext: automaticRewriteContext,
            memoryContext: personalMemoryContext,
            userIdentity: identityContext
          )
        }
        let result = try await withTaskCancellationHandler {
          try await rewriteWorker.value
        } onCancel: {
          rewriteWorker.cancel()
        }
        try Task.checkCancellation()
        switch result {
        case .completed(let rawTranscript, let finalText, let fallbackNote):
          onRewriteFallback?(fallbackNote)
          phase = .done(finalText)
          onRun?(
            ArchiveRunRecord(
              mode: mode,
              rawTranscript: rawTranscript,
              finalText: finalText,
              backend: transcriptionBackend,
              durationSec: recordingDuration
            )
          )
          onOutput?(finalText)
          WorkflowLatencyDiagnostics.logStage(
            .total,
            mode: mode,
            backend: transcriptionBackend,
            startedAt: totalStartedAt
          )
        case .variants(let variants, let fallbackNote):
          onRewriteFallback?(fallbackNote)
          phase = .variantChoice(variants.variants)
          onVariants?(variants)
          WorkflowLatencyDiagnostics.logEvent(
            "variant_choice_ready",
            mode: mode,
            backend: transcriptionBackend
          )
        }
      } catch {
        phase = .error(error.localizedDescription)
      }
    }
  }
}
