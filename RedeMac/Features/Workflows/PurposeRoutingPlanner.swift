import Foundation

/// Decides whether a run may use Automatik and, if so, assembles its plan. Pure.
///
/// Eligibility (all required): global master on, the mode switched to Automatik, secure-local off,
/// an online rewrite, a rewriting mode kind (`ModeKind.rewritesText`: rewrite and emoji, not plain
/// dictation), an API key — and the focused field is not a secure text field. Routing never turns
/// on field context, memory or e-mail memory: it only reuses what the mode already captured.
enum PurposeRoutingPlanner {
  struct Inputs {
    var settings: AppSettings
    var config: ModeConfig
    var rewriteBackend: RewriteBackend
    var hasAPIKey: Bool
    var targetIsSecureField: Bool
    var appName: String?
    var selection: SelectionContext?
    var automaticContext: AutomaticRewriteContext?
  }

  static func plan(_ inputs: Inputs, router: any PurposeRouting) -> PurposeRoutingPlan? {
    guard !inputs.targetIsSecureField else { return nil }
    let blocked = PurposeRoutingEligibility.resolve(
      masterEnabled: inputs.settings.purposeRoutingEnabled,
      modeAutomatic: inputs.config.rewrite.purposeRouting.isAutomatic,
      secureLocal: inputs.settings.secureLocalModeEnabled,
      rewriteIsOpenAI: inputs.rewriteBackend == .openai,
      kindRewrites: inputs.config.kind.rewritesText,
      hasAPIKey: inputs.hasAPIKey)
    guard blocked == nil else { return nil }
    return PurposeRoutingPlan(
      router: router,
      appName: inputs.appName,
      selection: inputs.selection,
      automaticContext: inputs.automaticContext,
      includesFieldText: inputs.settings.purposeRoutingIncludesFieldText)
  }
}
