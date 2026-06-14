import Foundation

enum PromptImprovementError: LocalizedError {
  case noRewriteEngine
  case emptyResult

  var errorDescription: String? {
    switch self {
    case .noRewriteEngine:
      return "Verbinde zuerst einen OpenAI-Key oder ein lokales LLM."
    case .emptyResult:
      return "Das Modell hat keinen verbesserten Prompt zurückgegeben."
    }
  }
}

enum PromptImprovementService {
  static let systemPrompt = """
    # Role

    You are a senior prompt engineer improving system prompts for a macOS voice-to-text app.

    # Objective

    Rewrite the supplied system prompt so it becomes clearer, more reliable, and easier for a chat
    model to follow. Use practical prompt-engineering principles: explicit role and objective,
    tight input/output contracts, preservation of user intent, clear constraints, examples only
    when useful, and no hidden chain-of-thought requirements.

    # Constraints

    - Preserve the mode's purpose and every important behavioral requirement.
    - Prefer structured Markdown sections with short headings.
    - Keep the output in the same language as the supplied prompt unless the prompt is empty.
    - For German app modes, write natural German instructions.
    - Do not add product claims, safety theater, or vague motivational language.
    - Return only the improved system prompt. No explanation, no wrapper, no code fence.
    """

  static func userText(modeName: String, modeKind: ModeKind, sourcePrompt: String) -> String {
    """
    Mode name: \(modeName)
    Mode kind: \(modeKind.rawValue)

    Current system prompt:
    \(sourcePrompt)
    """
  }

  static func cleanedOutput(_ text: String) -> String {
    var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if output.hasPrefix("```") {
      output.removeFirst(3)
      if let newline = output.firstIndex(of: "\n") {
        output = String(output[output.index(after: newline)...])
      }
      if output.hasSuffix("```") {
        output.removeLast(3)
      }
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

@MainActor
extension AppState {
  var canImproveSystemPrompts: Bool {
    appSettings.secureLocalModeEnabled ? promptImprovementLocalModelID != nil : hasOpenAIKey
  }

  var promptImprovementEngineLabel: String {
    if appSettings.secureLocalModeEnabled, let localModelID = promptImprovementLocalModelID {
      return localModelManager.installedLlamaCppModel(for: localModelID)?.displayName ?? "lokales LLM"
    }
    return hasOpenAIKey ? "OpenAI" : "kein modell"
  }

  func improveSystemPrompt(for config: ModeConfig) async -> Result<String, Error> {
    let provider: any RewriteProvider
    if appSettings.secureLocalModeEnabled, let localModelID = promptImprovementLocalModelID {
      provider = LlamaCppRewriteProvider(modelID: localModelID)
    } else if !appSettings.secureLocalModeEnabled, hasOpenAIKey {
      provider = OpenAIRewriteProvider(modelID: RewriteModelRegistry.strongModelID)
    } else {
      return .failure(PromptImprovementError.noRewriteEngine)
    }

    let sourcePrompt = promptImprovementSourcePrompt(for: config)
    do {
      let outcome = try await provider.rewrite(
        systemPrompt: PromptImprovementService.systemPrompt,
        userText: PromptImprovementService.userText(
          modeName: displayName(for: config),
          modeKind: config.kind,
          sourcePrompt: sourcePrompt
        ),
        temperature: 0.2
      )
      let improvedPrompt = PromptImprovementService.cleanedOutput(outcome.text)
      guard !improvedPrompt.isEmpty else {
        return .failure(PromptImprovementError.emptyResult)
      }
      return .success(improvedPrompt)
    } catch {
      return .failure(error)
    }
  }

  private var promptImprovementLocalModelID: String? {
    let selection = appSettings.selectedLocalLLM
    if selection.isConfigured,
      selection.runtime == .llamaCpp,
      localModelManager.isLlamaCppInstalled(selection.modelID)
    {
      return selection.modelID
    }
    return localModelManager.llamaCppInstalled.first?.id
  }

  private func promptImprovementSourcePrompt(for config: ModeConfig) -> String {
    let customPrompt = config.rewrite.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !customPrompt.isEmpty { return customPrompt }

    switch config.kind {
    case .transcribeThenEmoji:
      return LLMService.emojiSystemPrompt(config.rewrite, customTerms: [])
    case .transcribeThenRewrite:
      return LLMService.rewriteSystemPrompt(
        config.rewrite,
        customTerms: [],
        selection: nil,
        memory: nil
      )
    case .transcribeOnly:
      return ""
    }
  }
}
