import Foundation

struct MainPageReadinessIssue: Identifiable, Equatable {
  let id: String
  let message: String
}

@MainActor
extension AppState {
  var mainPageReadinessIssues: [MainPageReadinessIssue] {
    var localWhisperModes: [String] = []
    var localLLMModes: [String] = []
    var openAIModes: [String] = []

    for config in mainMenuModeConfigs where config.isEnabled {
      let modeName = displayName(for: config)
      collectTranscriptionReadiness(
        for: config,
        modeName: modeName,
        localWhisperModes: &localWhisperModes,
        openAIModes: &openAIModes
      )
      collectRewriteReadiness(
        for: config,
        modeName: modeName,
        localLLMModes: &localLLMModes,
        openAIModes: &openAIModes
      )
    }

    var issues: [MainPageReadinessIssue] = []
    if !localWhisperModes.isEmpty {
      issues.append(
        MainPageReadinessIssue(
          id: "local-whisper",
          message:
            "\(Self.readinessModeList(localWhisperModes)) läuft lokal, aber Whisper „\(selectedLocalModelDisplayName)“ ist nicht geladen."
        ))
    }
    if !localLLMModes.isEmpty {
      issues.append(
        MainPageReadinessIssue(
          id: "local-llm",
          message:
            "\(Self.readinessModeList(localLLMModes)) nutzt ein lokales LLM, aber \(localLLMReadinessLabel) ist nicht geladen."
        ))
    }
    if !openAIModes.isEmpty {
      issues.append(
        MainPageReadinessIssue(
          id: "openai-key",
          message:
            "\(Self.readinessModeList(openAIModes)) nutzt OpenAI, aber der API-Key fehlt."
        ))
    }
    return issues
  }

  private func collectTranscriptionReadiness(
    for config: ModeConfig,
    modeName: String,
    localWhisperModes: inout [String],
    openAIModes: inout [String]
  ) {
    switch config.slot {
    case .localTranscription:
      if !selectedLocalModelIsInstalled {
        localWhisperModes.append(modeName)
      }
    case .transcription, .textImprover, .dampfAblassen, .emojiText:
      if appSettings.secureLocalModeEnabled {
        if !selectedLocalModelIsInstalled {
          localWhisperModes.append(modeName)
        }
      } else if !hasOpenAIKey {
        openAIModes.append(modeName)
      }
    }
  }

  private func collectRewriteReadiness(
    for config: ModeConfig,
    modeName: String,
    localLLMModes: inout [String],
    openAIModes: inout [String]
  ) {
    switch config.slot {
    case .transcription, .localTranscription:
      return
    case .textImprover, .dampfAblassen, .emojiText:
      switch resolvedRewriteBackend(for: config) {
      case .local:
        if !selectedLocalLLMIsReady {
          localLLMModes.append(modeName)
        }
      case .openai:
        if !hasOpenAIKey {
          openAIModes.append(modeName)
        }
      }
    }
  }

  private var selectedLocalLLMIsReady: Bool {
    let selection = appSettings.selectedLocalLLM
    return selection.isConfigured
      && selection.runtime == .llamaCpp
      && localModelManager.isLlamaCppInstalled(selection.modelID)
  }

  private var localLLMReadinessLabel: String {
    let selection = appSettings.selectedLocalLLM
    guard selection.isConfigured else { return "kein GGUF-Modell" }
    if let installed = localModelManager.installedLlamaCppModel(for: selection.modelID) {
      return "„\(installed.displayName)“"
    }
    if let catalogModel = LlamaCppModelCatalog.model(for: selection.modelID) {
      return "„\(catalogModel.displayName)“"
    }
    return "„\(selection.modelID)“"
  }

  private static func readinessModeList(_ names: [String]) -> String {
    let uniqueNames = names.reduce(into: [String]()) { result, name in
      guard !result.contains(name) else { return }
      result.append(name)
    }
    switch uniqueNames.count {
    case 0:
      return "dieser modus"
    case 1:
      return uniqueNames[0]
    case 2:
      return "\(uniqueNames[0]) und \(uniqueNames[1])"
    default:
      return "\(uniqueNames[0]), \(uniqueNames[1]) + \(uniqueNames.count - 2) weitere"
    }
  }
}
