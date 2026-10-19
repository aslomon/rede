import Foundation

/// Composition root for everything that can reach OpenAI. Every production client is built here
/// (or at the single call sites that pass `remoteGate.allowsRemote`) so secure-local is enforced
/// inside the client on every attempt, not only where a feature is switched on.
extension AppState {
  /// Reasoning effort actually sent for a mode: the stored choice when the model supports it,
  /// the model default otherwise (Luna: `none`; models without efforts: nil = field omitted).
  func resolvedReasoningEffort(for config: ModeConfig) -> RewriteReasoningEffort? {
    RewriteModelRegistry.resolvedEffort(
      modelID: config.rewrite.modelID, stored: config.rewrite.reasoningEffort)
  }

  func openAIRewriteProvider(for config: ModeConfig) -> OpenAIRewriteProvider {
    OpenAIRewriteProvider(
      modelID: config.rewrite.modelID,
      reasoningEffort: resolvedReasoningEffort(for: config),
      isRemoteAllowed: remoteGate.allowsRemote)
  }

  /// Why live cannot run right now, or `.available`. Pure policy over current settings.
  func liveAvailability(backend: TranscriptionBackend) -> LiveAvailability {
    LiveAvailability.resolve(
      featureEnabled: appSettings.liveTranscriptionEnabled,
      secureLocal: appSettings.secureLocalModeEnabled,
      backendIsRemote: backend == .remote,
      hasAPIKey: hasOpenAIKey,
      microphoneAuthorized: MicrophonePermissionService.currentStatus.isGranted)
  }

  /// The remote wiring for one run. `live` is non-nil only when live is opted in and available.
  func workflowRemoteContext(backend: TranscriptionBackend) -> WorkflowRemoteContext {
    let gate = remoteGate
    var context = WorkflowRemoteContext(isRemoteAllowed: gate.allowsRemote)
    if liveAvailability(backend: backend) == .available {
      context.live = WorkflowLiveSupport(makeSession: {
        LiveTranscriptionController(
          isRemoteAllowed: gate.allowsRemote,
          apiKey: { KeychainService.load(key: .openAIAPIKey) })
      })
    }
    return context
  }

  /// Automatik plan for one run, or nil when the run is not eligible (see `PurposeRoutingPlanner`).
  /// It only reuses the context the mode already captured; it never reads anything itself.
  func purposeRoutingPlan(
    for config: ModeConfig, targetIsSecureField: Bool, appName: String?,
    selection: SelectionContext?, automaticContext: AutomaticRewriteContext?
  ) -> PurposeRoutingPlan? {
    PurposeRoutingPlanner.plan(
      PurposeRoutingPlanner.Inputs(
        settings: appSettings, config: config,
        rewriteBackend: resolvedRewriteBackend(for: config), hasAPIKey: hasOpenAIKey,
        targetIsSecureField: targetIsSecureField, appName: appName,
        selection: selection, automaticContext: automaticContext),
      router: Self.makePurposeRouter(isRemoteAllowed: remoteGate.allowsRemote))
  }

  /// The ONE place the Automatik router is built. The same live policy closure guards the router's
  /// own checks AND the Decisions client with its Keychain-backed transport, so a policy change
  /// while the credential is still being read stops the request before it leaves the process.
  /// A router built from its default client would carry an always-true transport gate instead.
  /// `makeClient` is a test seam only: it receives the very closure the router uses.
  static func makePurposeRouter(
    isRemoteAllowed: @escaping @Sendable () -> Bool,
    makeClient: (@escaping @Sendable () -> Bool) -> DecisionsClient = {
      DecisionsClient(isRemoteAllowed: $0)
    }
  ) -> DecisionsPurposeRouter {
    DecisionsPurposeRouter(client: makeClient(isRemoteAllowed), isRemoteAllowed: isRemoteAllowed)
  }
}
