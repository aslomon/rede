import Foundation

/// A source of text embeddings. The only implementation is the local llama.cpp provider below;
/// the protocol is kept so call sites stay decoupled from the transport.
protocol EmbeddingProvider: Sendable {
  var modelID: String { get }
  func embed(_ text: String) async throws -> [Double]
}

/// Embedding provider backed by a dedicated local llama.cpp server started with `--embedding`.
/// Drop-in replacement for the removed Ollama embedding provider — semantic e-mail memory uses
/// this so no text ever leaves the Mac and Ollama is no longer required.
struct LlamaCppEmbeddingProvider: EmbeddingProvider {
  static let defaultModelID = LlamaCppModelCatalog.defaultEmbeddingModel.id

  let modelID: String
  private let runtime: LlamaCppRuntimeService

  init(modelID: String = Self.defaultModelID, runtime: LlamaCppRuntimeService = .shared) {
    self.modelID = modelID
    self.runtime = runtime
  }

  func embed(_ text: String) async throws -> [Double] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw LlamaCppEmbeddingError.emptyInput }
    do {
      let client = try await runtime.embeddingClient(for: modelID)
      return try await client.embed(modelID: modelID, text: trimmed)
    } catch let runtimeError as LlamaCppRuntimeService.RuntimeError {
      throw LlamaCppEmbeddingError.modelUnavailable(runtimeError.localizedDescription)
    }
  }
}

enum LlamaCppEmbeddingError: LocalizedError, Equatable {
  case emptyInput
  case modelUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .emptyInput:
      return "Kein Text für das lokale Embedding vorhanden."
    case .modelUnavailable(let message):
      return message
    }
  }
}
