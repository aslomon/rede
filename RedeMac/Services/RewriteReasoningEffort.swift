import Foundation

enum RewriteReasoningEffort: String, Codable, CaseIterable, Sendable {
  case none
  case low
  case medium
  case high
  case xhigh
  case max
}

enum OpenAIRewriteConfigurationError: LocalizedError, Equatable, Sendable {
  case unsupportedReasoningEffort(modelID: String, effort: RewriteReasoningEffort)

  var errorDescription: String? {
    switch self {
    case .unsupportedReasoningEffort(let modelID, let effort):
      return "Modell \(modelID) unterstützt den Denkaufwand \(effort.rawValue) nicht."
    }
  }
}
