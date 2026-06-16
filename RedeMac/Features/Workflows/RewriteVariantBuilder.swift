import Foundation

enum RewriteVariantBuilder {
  static func secondVariantPrompt(_ systemPrompt: String) -> String {
    systemPrompt
      + "\n\nErzeuge diesmal eine zweite, klar alternative Version derselben Nachricht. "
      + "Behalte alle Fakten exakt bei, aber variiere Struktur, Rhythmus und Formulierungen sinnvoll."
  }

  static func uniqueVariants(first: String, second: String) -> [RewriteVariant] {
    let firstTrimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
    let secondTrimmed = second.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !firstTrimmed.isEmpty else { return [] }
    if secondTrimmed.isEmpty || secondTrimmed == firstTrimmed {
      return [RewriteVariant(title: "Version 1", text: firstTrimmed)]
    }
    return [
      RewriteVariant(title: "Version 1", text: firstTrimmed),
      RewriteVariant(title: "Version 2", text: secondTrimmed),
    ]
  }

  static func fallbackNote(primary: RewriteOutcome, secondary: RewriteOutcome) -> String? {
    RewriteModelRegistry.fallbackNote(
      requested: secondary.requestedModelID, used: secondary.usedModelID)
      ?? RewriteModelRegistry.fallbackNote(
        requested: primary.requestedModelID, used: primary.usedModelID)
  }
}
