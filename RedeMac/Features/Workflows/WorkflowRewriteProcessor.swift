import Foundation

enum WorkflowRewriteProcessingResult: Sendable {
  case completed(rawTranscript: String, finalText: String, fallbackNote: String?)
  case variants(PendingRewriteVariants, fallbackNote: String?)
}

enum WorkflowRewriteProcessor {
  static func textImprovementResult(
    cleanedRawText: String,
    recordingDuration: TimeInterval,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    rewrite: RewriteConfig,
    provider: any RewriteProvider,
    rewriteTerms: [String],
    selection: SelectionContext?,
    automaticContext: AutomaticRewriteContext?,
    memoryContext: MemoryContext?,
    userIdentity: UserIdentityContext?,
    emailMemoryLevel: SemanticEmailEnrichmentLevel,
    emailMemoryLoader: EmailMemoryMatchLoader?
  ) async throws -> WorkflowRewriteProcessingResult {
    let memoryStartedAt = Date()
    let emailMemoryMatches = await emailMemoryLoader?(cleanedRawText) ?? []
    WorkflowLatencyDiagnostics.logStage(
      .memoryContextRetrieval,
      mode: mode,
      backend: backend,
      startedAt: memoryStartedAt
    )
    let emailMemoryContext =
      emailMemoryMatches.isEmpty
      ? nil
      : EmailSemanticMemoryContext(matches: emailMemoryMatches, level: emailMemoryLevel)

    let promptStartedAt = Date()
    let systemPrompt = LLMService.rewriteSystemPrompt(
      rewrite,
      customTerms: rewriteTerms,
      selection: selection,
      automaticContext: automaticContext,
      memory: memoryContext,
      userIdentity: userIdentity,
      emailMemory: emailMemoryContext)
    WorkflowLatencyDiagnostics.logStage(
      .promptConstruction,
      mode: mode,
      backend: backend,
      startedAt: promptStartedAt
    )

    if rewrite.showTwoVariants, backend == .remote {
      return try await WorkflowRewriteVariantProcessor.resultWithConcurrentVariant(
        cleanedRawText: cleanedRawText,
        recordingDuration: recordingDuration,
        mode: mode,
        backend: backend,
        provider: provider,
        systemPrompt: systemPrompt,
        temperature: LLMService.defaultRewriteTemperature,
        rejectsNoSpeechSentinel: false
      )
    }

    let outcome = try await WorkflowRewriteVariantProcessor.firstRewrite(
      provider: provider,
      systemPrompt: systemPrompt,
      userText: cleanedRawText,
      temperature: LLMService.defaultRewriteTemperature,
      mode: mode,
      backend: backend
    )
    let finalText = TranscriptionQualityService.cleanedTranscript(outcome.text)
    return try await WorkflowRewriteVariantProcessor.resultWithOptionalVariant(
      firstText: finalText,
      firstOutcome: outcome,
      cleanedRawText: cleanedRawText,
      recordingDuration: recordingDuration,
      mode: mode,
      backend: backend,
      rewrite: rewrite,
      provider: provider,
      systemPrompt: systemPrompt,
      temperature: LLMService.defaultRewriteTemperature,
      rejectsNoSpeechSentinel: false
    )
  }

  static func dampfAblassenResult(
    cleanedRawText: String,
    recordingDuration: TimeInterval,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    rewrite: RewriteConfig,
    provider: any RewriteProvider,
    rewriteTerms: [String],
    automaticContext: AutomaticRewriteContext?,
    memoryContext: MemoryContext?,
    userIdentity: UserIdentityContext?
  ) async throws -> WorkflowRewriteProcessingResult {
    logNoLookupMemoryStage(mode: mode, backend: backend)
    let promptStartedAt = Date()
    let systemPrompt = LLMService.rewriteSystemPrompt(
      rewrite,
      customTerms: rewriteTerms,
      selection: nil,
      automaticContext: automaticContext,
      memory: memoryContext,
      userIdentity: userIdentity)
    WorkflowLatencyDiagnostics.logStage(
      .promptConstruction,
      mode: mode,
      backend: backend,
      startedAt: promptStartedAt
    )

    if rewrite.showTwoVariants, backend == .remote {
      return try await WorkflowRewriteVariantProcessor.resultWithConcurrentVariant(
        cleanedRawText: cleanedRawText,
        recordingDuration: recordingDuration,
        mode: mode,
        backend: backend,
        provider: provider,
        systemPrompt: systemPrompt,
        temperature: 0.4,
        rejectsNoSpeechSentinel: true
      )
    }

    let outcome = try await WorkflowRewriteVariantProcessor.firstRewrite(
      provider: provider,
      systemPrompt: systemPrompt,
      userText: cleanedRawText,
      temperature: 0.4,
      mode: mode,
      backend: backend
    )
    let finalText = TranscriptionQualityService.cleanedTranscript(outcome.text)
    guard finalText != "KEINE_AUFNAHME_ERKANNT" else {
      throw WorkflowProcessingError.noSpeech
    }

    return try await WorkflowRewriteVariantProcessor.resultWithOptionalVariant(
      firstText: finalText,
      firstOutcome: outcome,
      cleanedRawText: cleanedRawText,
      recordingDuration: recordingDuration,
      mode: mode,
      backend: backend,
      rewrite: rewrite,
      provider: provider,
      systemPrompt: systemPrompt,
      temperature: 0.4,
      rejectsNoSpeechSentinel: true
    )
  }

  static func emojiResult(
    cleanedRawText: String,
    recordingDuration: TimeInterval,
    mode: WorkflowType,
    backend: TranscriptionBackend,
    rewrite: RewriteConfig,
    provider: any RewriteProvider,
    rewriteTerms: [String]
  ) async throws -> WorkflowRewriteProcessingResult {
    logNoLookupMemoryStage(mode: mode, backend: backend)
    let promptStartedAt = Date()
    let systemPrompt = LLMService.emojiSystemPrompt(rewrite, customTerms: rewriteTerms)
    WorkflowLatencyDiagnostics.logStage(
      .promptConstruction,
      mode: mode,
      backend: backend,
      startedAt: promptStartedAt
    )

    if rewrite.showTwoVariants, backend == .remote {
      return try await WorkflowRewriteVariantProcessor.resultWithConcurrentVariant(
        cleanedRawText: cleanedRawText,
        recordingDuration: recordingDuration,
        mode: mode,
        backend: backend,
        provider: provider,
        systemPrompt: systemPrompt,
        temperature: LLMService.defaultRewriteTemperature,
        rejectsNoSpeechSentinel: true
      )
    }

    let outcome = try await WorkflowRewriteVariantProcessor.firstRewrite(
      provider: provider,
      systemPrompt: systemPrompt,
      userText: cleanedRawText,
      temperature: LLMService.defaultRewriteTemperature,
      mode: mode,
      backend: backend
    )
    let finalText = TranscriptionQualityService.cleanedTranscript(outcome.text)
    guard finalText != "KEINE_AUFNAHME_ERKANNT" else {
      throw WorkflowProcessingError.noSpeech
    }

    return try await WorkflowRewriteVariantProcessor.resultWithOptionalVariant(
      firstText: finalText,
      firstOutcome: outcome,
      cleanedRawText: cleanedRawText,
      recordingDuration: recordingDuration,
      mode: mode,
      backend: backend,
      rewrite: rewrite,
      provider: provider,
      systemPrompt: systemPrompt,
      temperature: LLMService.defaultRewriteTemperature,
      rejectsNoSpeechSentinel: true
    )
  }

  private static func logNoLookupMemoryStage(mode: WorkflowType, backend: TranscriptionBackend) {
    WorkflowLatencyDiagnostics.logStage(
      .memoryContextRetrieval,
      mode: mode,
      backend: backend,
      startedAt: Date()
    )
  }
}
