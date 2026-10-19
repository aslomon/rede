import Foundation

/// The last step the rewriting workflows share: hand a finished rewrite to the handlers (fallback
/// note, run record, output or variant choice). One copy, so a fix lands in every workflow.
@MainActor
protocol RewriteResultDelivering: Workflow {
  var onRewriteFallback: WorkflowRewriteFallbackHandler? { get }
  var onVariants: WorkflowVariantChoiceHandler? { get }
}

extension RewriteResultDelivering {
  func deliver(
    _ result: WorkflowRewriteProcessingResult, mode: WorkflowType,
    backend: TranscriptionBackend, recordingDuration: TimeInterval, totalStartedAt: Date
  ) {
    switch result {
    case .completed(let rawTranscript, let finalText, let fallbackNote):
      onRewriteFallback?(fallbackNote)
      phase = .done(finalText)
      onRun?(
        ArchiveRunRecord(
          mode: mode,
          rawTranscript: rawTranscript,
          finalText: finalText,
          backend: backend,
          durationSec: recordingDuration
        )
      )
      onOutput?(finalText)
      WorkflowLatencyDiagnostics.logStage(
        .total,
        mode: mode,
        backend: backend,
        startedAt: totalStartedAt
      )
    case .variants(let variants, let fallbackNote):
      onRewriteFallback?(fallbackNote)
      phase = .variantChoice(variants.variants)
      onVariants?(variants)
      WorkflowLatencyDiagnostics.logEvent(
        "variant_choice_ready",
        mode: mode,
        backend: backend
      )
    }
  }
}

extension TextImprovementWorkflow: RewriteResultDelivering {}
extension DampfAblassenWorkflow: RewriteResultDelivering {}
extension EmojiTextWorkflow: RewriteResultDelivering {}
