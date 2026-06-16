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
      recorder.stopRecording()
      guard
        !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration)
      else {
        recorder.discardRecording()
        phase = .error(TranscriptionQualityService.noSpeechMessage)
        return
      }
      processRecording()
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

  private func processRecording() {
    guard let url = recorder.recordingURL else {
      phase = .error("Keine Aufnahme vorhanden.")
      return
    }

    phase = .running("wird transkribiert …")
    let recordingDuration = recorder.lastRecordingDuration
    let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []

    processingTask = Task {
      // Optionally cut long pauses first; `audioURL` is the original when trimming is off/failed.
      let audioURL = await AudioRecorder.audioForTranscription(original: url)
      defer {
        try? FileManager.default.removeItem(at: url)
        if audioURL != url { try? FileManager.default.removeItem(at: audioURL) }
      }

      do {
        let rawText: String
        switch backend {
        case .remote:
          rawText = try await TranscriptionService.transcribe(
            audioURL: audioURL,
            customTerms: vocabularyHints,
            language: language
          )
        case .local:
          rawText = try await LocalTranscriptionService.shared.transcribe(
            audioURL: audioURL,
            language: language,
            modelName: localModelName,
            customTerms: vocabularyHints
          )
        }
        let cleanedRawText = FuzzyTermCorrector.correct(
          DictationPostProcessor.process(
            TranscriptionQualityService.cleanedTranscript(rawText), dictionary: dictionary),
          terms: fuzzyTerms)
        guard
          !TranscriptionQualityService.isLikelyArtifact(
            cleanedRawText, recordingDuration: recordingDuration)
        else {
          phase = .error(TranscriptionQualityService.noSpeechMessage)
          return
        }

        if Task.isCancelled { return }

        phase = .running("wird umformuliert …")

        let systemPrompt = LLMService.rewriteSystemPrompt(
          rewrite,
          customTerms: rewriteTerms,
          selection: nil,
          automaticContext: automaticContext,
          memory: memoryContext,
          userIdentity: userIdentity)
        let outcome = try await provider.rewrite(
          systemPrompt: systemPrompt,
          userText: cleanedRawText,
          temperature: 0.4
        )
        let cleanedAnswer = TranscriptionQualityService.cleanedTranscript(outcome.text)
        guard cleanedAnswer != "KEINE_AUFNAHME_ERKANNT" else {
          phase = .error(TranscriptionQualityService.noSpeechMessage)
          return
        }
        if rewrite.showTwoVariants {
          do {
            let secondOutcome = try await provider.rewrite(
              systemPrompt: RewriteVariantBuilder.secondVariantPrompt(systemPrompt),
              userText: cleanedRawText,
              temperature: 0.4
            )
            let cleanedSecond = TranscriptionQualityService.cleanedTranscript(secondOutcome.text)
            guard cleanedSecond != "KEINE_AUFNAHME_ERKANNT" else {
              throw LLMError.noContent
            }
            let variants = RewriteVariantBuilder.uniqueVariants(
              first: cleanedAnswer, second: cleanedSecond)
            guard variants.count > 1 else {
              throw LLMError.noContent
            }
            onRewriteFallback?(
              RewriteVariantBuilder.fallbackNote(primary: outcome, secondary: secondOutcome))
            phase = .variantChoice(variants)
            onVariants?(
              PendingRewriteVariants(
                mode: type,
                rawTranscript: cleanedRawText,
                variants: variants,
                backend: backend,
                durationSec: recordingDuration
              )
            )
            return
          } catch {
            // One-variant fallback: keep the successful first rewrite and paste it normally.
          }
        }

        onRewriteFallback?(
          RewriteModelRegistry.fallbackNote(
            requested: outcome.requestedModelID, used: outcome.usedModelID))
        phase = .done(cleanedAnswer)
        onRun?(
          ArchiveRunRecord(
            mode: type,
            rawTranscript: cleanedRawText,
            finalText: cleanedAnswer,
            backend: backend,
            durationSec: recordingDuration
          )
        )
        onOutput?(cleanedAnswer)
      } catch {
        phase = .error(error.localizedDescription)
      }
    }
  }
}
