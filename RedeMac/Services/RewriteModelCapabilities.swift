import Foundation

extension RewriteModelRegistry {
  /// Exact aliases verified in official model cards; unknown snapshots stay unverified.
  static func supportedEfforts(for modelID: String) -> [RewriteReasoningEffort] {
    switch modelID {
    case "gpt-6-luna", "gpt-6-sol": return RewriteReasoningEffort.allCases
    case "gpt-6.1-sol": return RewriteReasoningEffort.allCases.filter { $0 != .none }
    default: return []
    }
  }

  static func selectableEfforts(for modelID: String) -> [RewriteReasoningEffort] {
    modelID == "gpt-6-luna" ? [.none, .medium, .high, .xhigh] : supportedEfforts(for: modelID)
  }

  /// Normalize stored settings here; direct provider arguments still undergo strict preflight.
  static func resolvedEffort(
    modelID: String, stored: RewriteReasoningEffort?
  ) -> RewriteReasoningEffort? {
    if let stored, supportedEfforts(for: modelID).contains(stored) { return stored }
    return defaultEffort(for: modelID)
  }

  private static func defaultEffort(for modelID: String) -> RewriteReasoningEffort? {
    modelID == "gpt-6-luna" ? RewriteReasoningEffort.none : nil
  }

  /// Nil intentionally remains 45 seconds, including omitted Sol effort, per the approved contract.
  static func requestTimeout(for effort: RewriteReasoningEffort?) -> TimeInterval {
    switch effort {
    case .medium: return 60
    case .high: return 75
    case .xhigh, .max: return 120
    default: return 45
    }
  }

  static func resourceTimeout(for effort: RewriteReasoningEffort?) -> TimeInterval {
    requestTimeout(for: effort)
  }
}
