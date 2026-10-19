import Foundation

/// One-time construction of the slot `ModeConfig`s from the pre-mode per-workflow settings.
///
/// Pure on purpose: the result depends only on its inputs, so the "existing installation keeps its
/// historical models, a new installation starts on the recommended one" rule is testable without
/// touching any settings file.
enum ModeMigration {
  struct LegacySettings {
    var textImprovement: TextImprovementSettings
    var dampfAblassen: DampfAblassenSettings
    var emojiText: EmojiTextSettings
  }

  /// Fills every missing slot mode and completes `modeOrder`; modes that already exist are kept
  /// untouched. `isExistingInstallation` keeps each slot's historical model (see
  /// `ModeConfig.legacyDefaultRewrite`); only a brand-new installation gets the recommended model.
  static func migratedModes(
    existing: [String: ModeConfig], order: [String],
    legacy: LegacySettings, isExistingInstallation: Bool
  ) -> (modes: [String: ModeConfig], order: [String]) {
    var modes = existing

    func defaultMode(_ slot: WorkflowType) -> ModeConfig {
      .default(for: slot, preservingLegacyModels: isExistingInstallation)
    }
    func ensure(_ slot: WorkflowType, _ build: () -> ModeConfig) {
      if modes[slot.rawValue] == nil { modes[slot.rawValue] = build() }
    }

    ensure(.transcription) { defaultMode(.transcription) }
    ensure(.localTranscription) { defaultMode(.localTranscription) }
    ensure(.textImprover) { textImproverMode(defaultMode(.textImprover), legacy.textImprovement) }
    ensure(.dampfAblassen) { promptMode(defaultMode(.dampfAblassen), legacy.dampfAblassen) }
    ensure(.emojiText) { socialMode(defaultMode(.emojiText), legacy.emojiText) }

    return (modes, completedOrder(order))
  }

  private static func textImproverMode(
    _ base: ModeConfig, _ legacy: TextImprovementSettings
  ) -> ModeConfig {
    var cfg = base
    if !legacy.customName.isEmpty { cfg.userName = legacy.customName }
    if !legacy.systemPrompt.isEmpty { cfg.rewrite.systemPrompt = legacy.systemPrompt }
    cfg.rewrite.tone = legacy.tone
    cfg.rewrite.context = legacy.context
    return cfg
  }

  private static func promptMode(
    _ base: ModeConfig, _ legacy: DampfAblassenSettings
  ) -> ModeConfig {
    var cfg = base
    if !legacy.customName.isEmpty { cfg.userName = legacy.customName }
    // Only keep a user-customized prompt; the stock "calm down" default is replaced by the curated
    // Prompt default.
    let stock = DampfAblassenSettings().systemPrompt
    if !legacy.systemPrompt.isEmpty, legacy.systemPrompt != stock {
      cfg.rewrite.systemPrompt = legacy.systemPrompt
    }
    return cfg
  }

  private static func socialMode(_ base: ModeConfig, _ legacy: EmojiTextSettings) -> ModeConfig {
    var cfg = base
    if !legacy.customName.isEmpty { cfg.userName = legacy.customName }
    cfg.rewrite.emojiDensity = legacy.emojiDensity
    return cfg
  }

  private static func completedOrder(_ order: [String]) -> [String] {
    guard !order.isEmpty else { return WorkflowType.allCases.map(\.rawValue) }
    var result = order
    for slot in WorkflowType.allCases where !result.contains(slot.rawValue) {
      result.append(slot.rawValue)
    }
    return result
  }
}
