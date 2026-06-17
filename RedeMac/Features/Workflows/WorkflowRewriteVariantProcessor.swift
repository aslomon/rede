import Foundation

enum WorkflowRewriteVariantProcessor {
  static func firstRewrite(
    provider: any RewriteProvider,
    systemPrompt: String,
    userText: String,
    temperature: Double,
    mode: WorkflowType,
    backend: TranscriptionBackend
  ) async throws -> RewriteOutcome {
    let rewriteStartedAt = Date()
    let outcome = try await provider.rewrite(
      systemPrompt: systemPrompt,
      userText: userText,
      temperature: temperature
    )
    WorkflowLatencyDiagnostics.logStage(
      .rewrite,
      mode: mode,
      backend: backend,
      startedAt: rewriteStartedAt
    )
    return outcome
  }

  static func resultWithOptionalVariant(
    firstText: String,
    firstOutcome: RewriteOutcome,
    cleanedRawText: String,
    recordingDuration: TimeInterval,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    rewrite: RewriteConfig,
    provider: any RewriteProvider,
    systemPrompt: String,
    temperature: Double,
    rejectsNoSpeechSentinel: Bool
  ) async throws -> WorkflowRewriteProcessingResult {
    if rewrite.showTwoVariants {
      do {
        let secondStartedAt = Date()
        let secondOutcome = try await provider.rewrite(
          systemPrompt: RewriteVariantBuilder.secondVariantPrompt(systemPrompt),
          userText: cleanedRawText,
          temperature: temperature
        )
        WorkflowLatencyDiagnostics.logStage(
          .secondVariant,
          mode: mode,
          backend: backend,
          startedAt: secondStartedAt
        )
        let cleanedSecond = TranscriptionQualityService.cleanedTranscript(secondOutcome.text)
        if rejectsNoSpeechSentinel, cleanedSecond == "KEINE_AUFNAHME_ERKANNT" {
          throw LLMError.noContent
        }
        let variants = RewriteVariantBuilder.uniqueVariants(
          first: firstText, second: cleanedSecond)
        guard variants.count > 1 else {
          throw LLMError.noContent
        }
        return .variants(
          PendingRewriteVariants(
            mode: mode,
            rawTranscript: cleanedRawText,
            variants: variants,
            backend: backend,
            durationSec: recordingDuration
          ),
          fallbackNote: RewriteVariantBuilder.fallbackNote(
            primary: firstOutcome, secondary: secondOutcome)
        )
      } catch {
        // One-variant fallback: keep the successful first rewrite and paste it normally.
      }
    }

    return .completed(
      rawTranscript: cleanedRawText,
      finalText: firstText,
      fallbackNote: RewriteModelRegistry.fallbackNote(
        requested: firstOutcome.requestedModelID, used: firstOutcome.usedModelID)
    )
  }

  static func resultWithConcurrentVariant(
    cleanedRawText: String,
    recordingDuration: TimeInterval,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    provider: any RewriteProvider,
    systemPrompt: String,
    temperature: Double,
    rejectsNoSpeechSentinel: Bool
  ) async throws -> WorkflowRewriteProcessingResult {
    let firstStartedAt = Date()
    async let firstOutcome = provider.rewrite(
      systemPrompt: systemPrompt,
      userText: cleanedRawText,
      temperature: temperature
    )
    let secondStartedAt = Date()
    async let secondOutcome = provider.rewrite(
      systemPrompt: RewriteVariantBuilder.secondVariantPrompt(systemPrompt),
      userText: cleanedRawText,
      temperature: temperature
    )

    let primary = try await firstOutcome
    WorkflowLatencyDiagnostics.logStage(
      .rewrite,
      mode: mode,
      backend: backend,
      startedAt: firstStartedAt
    )
    let firstText = TranscriptionQualityService.cleanedTranscript(primary.text)
    guard !rejectsNoSpeechSentinel || firstText != "KEINE_AUFNAHME_ERKANNT" else {
      throw WorkflowProcessingError.noSpeech
    }

    do {
      let secondary = try await secondOutcome
      WorkflowLatencyDiagnostics.logStage(
        .secondVariant,
        mode: mode,
        backend: backend,
        startedAt: secondStartedAt
      )
      let secondText = TranscriptionQualityService.cleanedTranscript(secondary.text)
      if rejectsNoSpeechSentinel, secondText == "KEINE_AUFNAHME_ERKANNT" {
        throw LLMError.noContent
      }
      let variants = RewriteVariantBuilder.uniqueVariants(first: firstText, second: secondText)
      guard variants.count > 1 else {
        throw LLMError.noContent
      }
      return .variants(
        PendingRewriteVariants(
          mode: mode,
          rawTranscript: cleanedRawText,
          variants: variants,
          backend: backend,
          durationSec: recordingDuration
        ),
        fallbackNote: RewriteVariantBuilder.fallbackNote(primary: primary, secondary: secondary)
      )
    } catch {
      return .completed(
        rawTranscript: cleanedRawText,
        finalText: firstText,
        fallbackNote: RewriteModelRegistry.fallbackNote(
          requested: primary.requestedModelID, used: primary.usedModelID)
      )
    }
  }
}
