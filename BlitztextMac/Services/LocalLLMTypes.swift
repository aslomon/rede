import Foundation

enum LocalLLMRuntimeKind: String, CaseIterable, Codable, Identifiable, Sendable {
  case llamaCpp
  case ollama

  var id: String { rawValue }

  var backendLabel: String {
    switch self {
    case .llamaCpp: return "Lokal (llama.cpp)"
    case .ollama: return OllamaService.backendLabel
    }
  }

  var displayName: String {
    switch self {
    case .llamaCpp: return "llama.cpp"
    case .ollama: return "Ollama"
    }
  }
}

struct LocalLLMSelection: Codable, Equatable, Sendable {
  var runtime: LocalLLMRuntimeKind
  var modelID: String

  init(runtime: LocalLLMRuntimeKind = .llamaCpp, modelID: String = "") {
    self.runtime = runtime
    self.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var isConfigured: Bool {
    !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct LocalLLMInstalledModel: Identifiable, Equatable, Sendable {
  let id: String
  let runtime: LocalLLMRuntimeKind
  let displayName: String
  let sizeBytes: Int64
  let parameterSize: String?
  let quantization: String?

  var sizeGB: Double { Double(sizeBytes) / 1_000_000_000.0 }
}
