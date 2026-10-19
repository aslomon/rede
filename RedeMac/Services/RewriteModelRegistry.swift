import Foundation

/// One selectable OpenAI rewrite model.
struct RewriteModelOption: Identifiable, Hashable {
  let id: String  // API model id, e.g. "gpt-4o"
  let label: String  // UI label
  let tier: String  // short hint, e.g. "Schnell" / "Qualität"
  let supportsTemperature: Bool

  var menuLabel: String { "\(label) · \(tier)" }

  /// Exact API aliases verified in the official model cards on 2026-10-19.
  /// Unknown and legacy models remain unverified rather than inheriting prefix-based support.
  var supportedReasoningEfforts: [RewriteReasoningEffort] {
    RewriteModelRegistry.supportedEfforts(for: id)
  }
}

/// Curated registry of OpenAI chat models usable for rewriting, plus helpers to
/// resolve unknown ids and to merge in models actually available on the account.
enum RewriteModelRegistry {
  // Stable, broadly available ids (safe fallbacks).
  static let defaultModelID = "gpt-4o"
  static let recommendedModelID = "gpt-6-luna"
  static let fastModelID = "gpt-4o-mini"
  /// Stronger newer model for high-quality language tasks (verified available June 2026).
  static let strongModelID = "gpt-5.4"
  /// Universal hard fallback when a chosen model id is rejected by the API.
  static let safeFallbackModelID = "gpt-4o-mini"

  /// Reasoning model defaults reject `temperature`; omit it until a supported non-reasoning
  /// configuration is explicitly selected.
  static let temperatureUnsupportedPrefixes = ["gpt-5", "gpt-6", "o1", "o3", "o4"]

  static let curated: [RewriteModelOption] = [
    RewriteModelOption(
      id: "gpt-6-luna", label: "GPT-6 Luna", tier: "Sehr schnell & günstig", supportsTemperature: false),
    RewriteModelOption(
      id: "gpt-4o-mini", label: "GPT-4o mini", tier: "Schnell & günstig", supportsTemperature: true),
    RewriteModelOption(
      id: "gpt-4o", label: "GPT-4o", tier: "Ausgewogen", supportsTemperature: true),
    RewriteModelOption(
      id: "gpt-5.4-mini", label: "GPT-5.4 mini", tier: "Schnell, neuer", supportsTemperature: false),
    RewriteModelOption(
      id: "gpt-5.4", label: "GPT-5.4", tier: "Stark für Sprache", supportsTemperature: false),
    RewriteModelOption(
      id: "gpt-5.5", label: "GPT-5.5", tier: "Maximale Qualität", supportsTemperature: false),
    RewriteModelOption(
      id: "gpt-6-sol", label: "GPT-6 Sol", tier: "Ausgewogen", supportsTemperature: false),
    RewriteModelOption(
      id: "gpt-6.1-sol", label: "GPT-6.1 Sol", tier: "Ausgewogen", supportsTemperature: false)
  ]

  // MARK: - Fallback note (B6)

  /// Builds the quiet, one-line German (du-form) note shown when a rewrite ran on a DIFFERENT model
  /// than requested. Returns `nil` when nothing changed (happy path) or either id is missing, so the
  /// UI shows the note only on a real fallback. The label, not the raw id, is used when curated.
  static func fallbackNote(requested: String?, used: String?) -> String? {
    guard let requested, let used, requested != used else { return nil }
    let requestedLabel = option(for: requested).label
    let usedLabel = option(for: used).label
    return "Modell \(requestedLabel) nicht verfügbar — \(usedLabel) verwendet."
  }

  static func supportsTemperature(_ modelID: String) -> Bool {
    if let known = curated.first(where: { $0.id == modelID }) {
      return known.supportsTemperature
    }
    let lowered = modelID.lowercased()
    return !temperatureUnsupportedPrefixes.contains { lowered.hasPrefix($0) }
  }

  static func option(for modelID: String) -> RewriteModelOption {
    curated.first { $0.id == modelID }
      ?? RewriteModelOption(
        id: modelID, label: modelID, tier: "Eigenes",
        supportsTemperature: supportsTemperature(modelID))
  }

  /// Merge curated options with any extra ids fetched from the account, preserving curated order.
  static func options(includingFetched fetched: [String]) -> [RewriteModelOption] {
    var result = curated
    let known = Set(curated.map { $0.id })
    for id in fetched where !known.contains(id) {
      result.append(
        RewriteModelOption(
          id: id, label: id, tier: "Account", supportsTemperature: supportsTemperature(id)))
    }
    return result
  }

}
