import Foundation

/// Everything the routing step needs for ONE run. Built only when the run is eligible (see
/// `PurposeRoutingPlanner`), so a nil plan means "do exactly what rede did before".
struct PurposeRoutingPlan: Sendable {
  let router: any PurposeRouting
  let appName: String?
  /// Only the selected text is ever read from it, never the surrounding text.
  let selection: SelectionContext?
  /// Present only when the mode itself already opted in to field context.
  let automaticContext: AutomaticRewriteContext?
  let includesFieldText: Bool
}

/// What the user sees after a routed run. The view maps this to German copy; it never promises
/// a perfect result.
enum PurposeRoutingNote: Equatable, Sendable {
  case detected(DictationPurpose)
  case noSpecialPurpose
  case fellBack(NeutralReason)
}

struct PurposeRoutingResult: Equatable, Sendable {
  let purpose: DictationPurpose
  let note: PurposeRoutingNote?
  /// Terminal: the caller must abort the whole run (no rewrite, no paste, no archive).
  let isCancelled: Bool

  /// Routing did not run: today's behavior, no note.
  static let skipped = PurposeRoutingResult(purpose: .other, note: nil, isCancelled: false)
  static let cancelled = PurposeRoutingResult(purpose: .other, note: nil, isCancelled: true)
}

/// Maps the context rede has ALREADY captured for this mode onto the four-field Decisions input.
/// Routing never reads anything itself: it cannot widen data access or flip a privacy setting.
enum DecisionContextAdapter {
  static func make(dictatedText: String, plan: PurposeRoutingPlan) -> DecisionContext {
    DecisionContext(
      dictatedText: dictatedText,
      selectedText: nonEmpty(plan.selection?.selectedText),
      appName: nonEmpty(plan.appName),
      fieldText: plan.includesFieldText ? nonEmpty(plan.automaticContext?.text) : nil)
  }

  private static func nonEmpty(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
  }
}

enum PurposeRoutingStep {
  /// Runs the router for one dictation. Never throws; every failure is a neutral `.other`.
  /// Cancellation is reported separately and must stop the run.
  static func run(plan: PurposeRoutingPlan?, dictatedText: String) async -> PurposeRoutingResult {
    guard let plan else { return .skipped }
    if Task.isCancelled { return .cancelled }
    let decision = await plan.router.route(
      DecisionContextAdapter.make(dictatedText: dictatedText, plan: plan))
    if decision.isCancelled || Task.isCancelled { return .cancelled }
    return PurposeRoutingResult(
      purpose: decision.purpose, note: note(for: decision), isCancelled: false)
  }

  private static func note(for decision: PurposeDecision) -> PurposeRoutingNote? {
    if let reason = decision.neutralReason {
      // Not eligible / blocked means the feature did not run at all: say nothing.
      switch reason {
      case .notEligible, .remoteNotAllowed, .noAPIKey, .cancelled: return nil
      default: return .fellBack(reason)
      }
    }
    return decision.purpose == .other ? .noSpecialPurpose : .detected(decision.purpose)
  }
}
