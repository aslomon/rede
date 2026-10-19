import Foundation

/// The optional, dismissible "Für Rewrite-Modi übernehmen" offer in the models window.
/// It is only ever shown; adopting is a separate, user-initiated call. Nothing here runs silently.
enum RecommendedModelOffer {
  static let offerID = RewriteModelRegistry.recommendedModelID

  /// Online rewrite modes that are not on the recommended model yet.
  static func candidateModeIDs(in modes: [String: ModeConfig]) -> [String] {
    modes.values
      .filter {
        $0.kind != .transcribeOnly && $0.rewrite.rewriteBackend == .openai
          && $0.rewrite.modelID != RewriteModelRegistry.recommendedModelID
      }
      .map(\.id)
      .sorted()
  }

  static func isVisible(
    modes: [String: ModeConfig], dismissedOffers: [String], onlineRewriteReady: Bool
  ) -> Bool {
    onlineRewriteReady && !dismissedOffers.contains(offerID)
      && !candidateModeIDs(in: modes).isEmpty
  }

  /// Moves exactly the candidate modes to the recommended model and clears their stored effort
  /// (the registry resolves "unset" to the model default). Other modes are untouched.
  static func adopting(_ modes: [String: ModeConfig]) -> [String: ModeConfig] {
    var updated = modes
    for id in candidateModeIDs(in: modes) {
      guard var mode = updated[id] else { continue }
      mode.rewrite.modelID = RewriteModelRegistry.recommendedModelID
      mode.rewrite.reasoningEffort = nil
      updated[id] = mode
    }
    return updated
  }

  static func dismissing(_ dismissedOffers: [String]) -> [String] {
    dismissedOffers.contains(offerID) ? dismissedOffers : dismissedOffers + [offerID]
  }
}
