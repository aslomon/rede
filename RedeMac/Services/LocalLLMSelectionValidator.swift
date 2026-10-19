import Foundation

/// Validates a PERSISTED local rewrite selection against what llama.cpp actually knows.
///
/// Decoding must not do this: the installed set is unknown at decode time, so a Hugging-Face model
/// that is installed but absent from the curated catalog (e.g. `hf-ggml-org-gemma-4-e4b-it-gguf`)
/// was silently discarded on every launch. The check lives where installed models are known.
enum LocalLLMSelectionValidator {
  /// Keeps the selection when the curated catalog OR an installed manifest knows the model id.
  /// Anything else — typically a removed Ollama tag such as `gemma3:latest` — becomes the empty
  /// selection so the user re-picks a GGUF model instead of every local rewrite failing.
  static func validated(
    _ selection: LocalLLMSelection, installedModelIDs: Set<String>
  ) -> LocalLLMSelection {
    guard selection.isConfigured else { return selection }
    let known =
      LlamaCppModelCatalog.chatModel(for: selection.modelID) != nil
      || installedModelIDs.contains(selection.modelID)
    return known ? selection : LocalLLMSelection()
  }
}
