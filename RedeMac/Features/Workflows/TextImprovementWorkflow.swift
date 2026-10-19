import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class TextImprovementWorkflow: Workflow {
  let type = WorkflowType.textImprover
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
  private let selection: SelectionContext?
  private let automaticContext: AutomaticRewriteContext?
  private let memoryContext: MemoryContext?
  private let userIdentity: UserIdentityContext?
  private let emailMemoryLevel: SemanticEmailEnrichmentLevel
  private let emailMemoryLoader: EmailMemoryMatchLoader?
  private var processingTask: Task<Void, Never>?
  private let remote: WorkflowRemoteContext
  private let routing: PurposeRoutingPlan?
  /// Fired once per run with what Automatik did (nil: it did not run). Display only.
  var onRoutingNote: ((PurposeRoutingNote?) -> Void)?
  private let runs = WorkflowRunTracker()
  private let transcriptionOverride: WorkflowTranscriptionOverride?

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
    selection: SelectionContext? = nil,
    automaticContext: AutomaticRewriteContext? = nil,
    memoryContext: MemoryContext? = nil,
    userIdentity: UserIdentityContext? = nil,
    emailMemoryLevel: SemanticEmailEnrichmentLevel = .medium,
    emailMemoryLoader: EmailMemoryMatchLoader? = nil,
    remote: WorkflowRemoteContext = WorkflowRemoteContext(),
    routing: PurposeRoutingPlan? = nil,
    transcriptionOverride: WorkflowTranscriptionOverride? = nil
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
    self.selection = selection
    self.automaticContext = automaticContext
    self.memoryContext = memoryContext
    self.userIdentity = userIdentity
    self.emailMemoryLevel = emailMemoryLevel
    self.emailMemoryLoader = emailMemoryLoader
    self.remote = remote
    self.routing = routing
    self.transcriptionOverride = transcriptionOverride
  }

  // MARK: - Recording State

  var isRecording: Bool { recorder.isRecording }
  var audioLevel: Float { recorder.audioLevel }
  var didTruncateAtMaxDuration: Bool { recorder.didStopAtMaxDuration }
  /// Live text while speaking (display only); nil unless live is active for this run.
  var liveTranscript: LiveTranscriptSnapshot? { remote.live?.snapshot }
  var liveDisplayState: LiveDisplayState? { remote.live?.displayState }

  // MARK: - Workflow Protocol

  func start() {
    // "Auswahl bearbeiten" needs real highlighted text; without it the rewrite would silently
    // improve something unrelated and auto-paste it. Fail fast BEFORE recording instead.
    if rewrite.replyContextMode == .editSelection,
      selection?.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    {
      phase = .error("Bitte zuerst Text markieren, dann „Auswahl bearbeiten“ starten.")
      return
    }

    // Recorder first so isRecording is true before .running fires (see TranscriptionWorkflow).
    recorder.startRecording()

    if let error = recorder.errorMessage {
      phase = .error(error)
      return
    }
    // Safety cap: if the recording runs past the max duration, stop+process what we have.
    recorder.onMaxDurationReached = { [weak self] in self?.stop() }
    remote.live?.begin(language: language, keywords: customTerms)
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
        remote.live?.cancel()
        phase = .error(TranscriptionQualityService.noSpeechMessage)
        return
      }
      processRecording(totalStartedAt: stopStartedAt)
    } else {
      processingTask?.cancel()
      remote.live?.cancel()
      runs.invalidate()
      phase = .idle
    }
  }

  func reset() {
    processingTask?.cancel()
    remote.live?.cancel()
    runs.invalidate()
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
    let selectionContext = selection
    let automaticRewriteContext = automaticContext
    let personalMemoryContext = memoryContext
    let identityContext = userIdentity
    let semanticEmailLevel = emailMemoryLevel
    let semanticEmailLoader = emailMemoryLoader

    let isRemoteAllowed = remote.isRemoteAllowed
    let liveSession = remote.live
    let routingPlan = routing
    let injected = transcriptionOverride
    let runID = runs.begin()
    processingTask = Task(priority: .userInitiated) {
      let liveText: String?
      do { liveText = try await liveSession?.finalTranscript() } catch { return }
      let transcriptionWorker = Task<WorkflowTranscriptionResult, Error>.detached(
        priority: .userInitiated
      ) {
        if let injected { return try await injected(url, liveText) }
        return try await WorkflowTranscriptionProcessor.transcribeAndClean(
          originalAudioURL: url,
          mode: mode,
          backend: transcriptionBackend,
          vocabularyHints: vocabularyHints,
          language: requestLanguage,
          localModelName: selectedLocalModelName,
          dictionary: dictationDictionary,
          fuzzyTerms: correctionTerms,
          silenceTrimmingEnabled: shouldTrimSilence,
          isRemoteAllowed: isRemoteAllowed,
          liveText: liveText
        )
      }
      do {
        let transcription = try await withTaskCancellationHandler {
          try await transcriptionWorker.value
        } onCancel: {
          transcriptionWorker.cancel()
        }
        // Cancel and run identity first: a worker that ignored the cancel and finished after
        // reset/new start must not touch phase, output or archive of the current run.
        try Task.checkCancellation()
        guard runs.isCurrent(runID) else { return }
        guard
          !TranscriptionQualityService.isLikelyArtifact(
            transcription.cleanedText, recordingDuration: recordingDuration)
        else {
          phase = .error(TranscriptionQualityService.noSpeechMessage)
          return
        }

        phase = .running("text wird verbessert …")
        // Automatik: one bounded decision. Cancel is terminal; any fallback continues unchanged.
        let routed = await PurposeRoutingStep.run(
          plan: routingPlan, dictatedText: transcription.cleanedText)
        if routed.isCancelled { return }
        guard runs.isCurrent(runID) else { return }
        onRoutingNote?(routed.note)
        let routedPurpose = routed.purpose
        let rewriteWorker = Task.detached(priority: .userInitiated) {
          try await WorkflowRewriteProcessor.textImprovementResult(
            cleanedRawText: transcription.cleanedText,
            recordingDuration: recordingDuration,
            mode: mode,
            backend: transcriptionBackend,
            rewrite: rewriteConfig,
            provider: rewriteProvider,
            rewriteTerms: rewritePromptTerms,
            selection: selectionContext,
            automaticContext: automaticRewriteContext,
            memoryContext: personalMemoryContext,
            userIdentity: identityContext,
            emailMemoryLevel: semanticEmailLevel,
            emailMemoryLoader: semanticEmailLoader,
            purpose: routedPurpose
          )
        }
        let result = try await withTaskCancellationHandler {
          try await rewriteWorker.value
        } onCancel: {
          rewriteWorker.cancel()
        }
        try Task.checkCancellation()
        guard runs.isCurrent(runID) else { return }
        deliver(
          result, mode: mode, backend: transcriptionBackend,
          recordingDuration: recordingDuration, totalStartedAt: totalStartedAt)
      } catch {
        if WorkflowCancellation.isTerminal(error) { return }
        guard runs.isCurrent(runID) else { return }
        phase = .error(error.localizedDescription)
      }
    }
  }

}

#if DEBUG
  extension TextImprovementWorkflow {
    /// Runs the pipeline on a given recording without the microphone (tests only).
    func processForTesting(audioURL: URL, recordingDuration: TimeInterval) {
      recorder.recordingURL = audioURL
      recorder.lastRecordingDuration = recordingDuration
      processRecording(totalStartedAt: Date())
    }

    var processingTaskForTesting: Task<Void, Never>? { processingTask }
  }
#endif
