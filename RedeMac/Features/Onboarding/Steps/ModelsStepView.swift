import SwiftUI

/// Step: the local engines. The Whisper picker + install controls mirror `ModelsSettingsView`'s
/// transcription block. Online and local processing are exclusive, so the step shows only the
/// model path selected in the previous step.
struct ModelsStepView: View {
  @Bindable var appState: AppState
  @State private var transcriptionRecheckToken = 0

  private var installedLocalModels: [LocalTranscriptionModel] {
    _ = transcriptionRecheckToken
    return LocalTranscriptionService.installedModels()
  }

  private var localModelOptions: [LocalTranscriptionModel] {
    _ = transcriptionRecheckToken
    return LocalTranscriptionService.modelOptions()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      if appState.appSettings.secureLocalModeEnabled {
        whisperCard
        localRewriteCard
      } else {
        onlineModelsCard
      }
    }
  }

  // MARK: - Whisper (transcription)

  private var whisperCard: some View {
    OnboardingCard(accent: !appState.selectedLocalModelIsInstalled ? .orange : nil)
    {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          SectionLabel(text: "Whisper (sprache → text)", icon: "waveform")
          Spacer()
          Button("prüfen") { transcriptionRecheckToken += 1 }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .disabled(appState.isDownloadingLocalModel)
        }

        // Download-in-progress status pill above controls (change 10)
        if appState.isDownloadingLocalModel {
          RedeStatusPill(state: .download, label: "download läuft — bitte warten")
        }

        stateRow
        modelPicker
        downloadControls
        if let errorText = appState.localModelDownloadErrorText {
          Text(errorText)
            .font(.system(size: 10.5))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var onlineModelsCard: some View {
    OnboardingCard(accent: appState.hasOpenAIKey ? nil : .orange) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          SectionLabel(text: "online-modelle", icon: "key.fill")
          Spacer()
          RedeStatusPill(
            state: appState.hasOpenAIKey ? .online : .warning,
            label: appState.hasOpenAIKey ? "OpenAI bereit" : "OpenAI fehlt"
          )
        }

        Text(
          appState.hasOpenAIKey
            ? "Whisper online und die umschreib-modelle laufen über die OpenAI-API. lokale modelle werden in diesem modus nicht verwendet."
            : "trage zuerst deinen OpenAI API-Key ein, damit online-transkription und umschreiben funktionieren."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var stateRow: some View {
    HStack(spacing: 6) {
      Image(
        systemName: appState.selectedLocalModelIsInstalled
          ? "checkmark.circle.fill" : "arrow.down.circle.fill"
      )
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(appState.selectedLocalModelIsInstalled ? .green : .blue)
      Text(stateText)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
  }

  private var stateText: String {
    if appState.selectedLocalModelIsInstalled {
      let count = installedLocalModels.count
      return
        "\u{201E}\(appState.selectedLocalModelDisplayName)\u{201C} ist geladen (\(count) Whisper-Modell(e))."
    }
    if let size = LocalTranscriptionModel.sizeLabel(for: appState.selectedLocalModelName) {
      return
        "\u{201E}\(appState.selectedLocalModelDisplayName)\u{201C} ist noch nicht geladen \u{2014} \(size)."
    }
    return "\u{201E}\(appState.selectedLocalModelDisplayName)\u{201C} ist noch nicht geladen."
  }

  private var modelPicker: some View {
    HStack(spacing: 8) {
      Text("modell")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker(
        "",
        selection: Binding(
          get: { appState.selectedLocalModelName },
          set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
        )
      ) {
        ForEach(localModelOptions) { model in
          Text("\(model.displayName) · \(model.installStateLabel)").tag(model.id)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .disabled(appState.isDownloadingLocalModel)
    }
  }

  @ViewBuilder
  private var downloadControls: some View {
    if let progress = appState.localModelDownloadProgress {
      VStack(alignment: .leading, spacing: 4) {
        ProgressView(value: progress)
        Text(appState.localModelDownloadStatusText ?? "modell wird geladen …")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
    } else {
      Button(appState.localModelDownloadButtonTitle) {
        appState.installSelectedLocalModel()
      }
      .controlSize(.small)
      .buttonStyle(
        PopoverActionButtonStyle(appState.selectedLocalModelIsInstalled ? .secondary : .primary)
      )
      .disabled(appState.selectedLocalModelIsInstalled || appState.isDownloadingLocalModel)
    }
  }

  // MARK: - Local rewrite model — optional

  private var localRewriteCard: some View {
    OnboardingCard {
      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "lokales sprachmodell", icon: "text.bubble")
        InfoDisclosure("wofür") {
          Text(
            "formuliert E-Mail, Prompt und Social lokal über den gebündelten llama.cpp-Helper um. nötig für umschreib-modi, wenn verarbeitung auf lokal steht."
          )
        }

        LocalLLMModelPicker(appState: appState)
      }
    }
  }
}
