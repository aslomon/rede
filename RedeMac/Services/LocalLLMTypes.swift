import Foundation

/// The local rewrite runtime. llama.cpp is the only one — the enum is kept (rather than removed)
/// so `LocalLLMSelection` and old settings files stay source- and forward-compatible.
enum LocalLLMRuntimeKind: String, CaseIterable, Codable, Identifiable, Sendable {
  case llamaCpp

  var id: String { rawValue }

  var backendLabel: String { "Lokal (llama.cpp)" }

  var displayName: String { "llama.cpp" }

  /// Tolerant decoder: any legacy value (e.g. the removed "ollama") maps to llama.cpp, so old
  /// settings files still decode after Ollama was dropped.
  init(from decoder: Decoder) throws {
    _ = try decoder.singleValueContainer().decode(String.self)
    self = .llamaCpp
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
