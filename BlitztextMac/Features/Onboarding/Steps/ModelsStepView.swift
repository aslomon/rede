import SwiftUI

/// Step: the local engines. The Whisper picker + install controls mirror `ModelsSettingsView`'s
/// transcription block (only relevant in offline mode); the local rewrite model is always shown,
/// but labelled optional because online rewriting never needs it.
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
      OnboardingStepHeader(
        systemImage: "shippingbox",
        accent: .green,
        title: "lokale modelle",
        subtitle: needsWhisper
          ? "lade ein lokales Whisper-Modell." : "im online-modus ist hier nichts pflicht."
      )

      whisperCard

      // Local rewrite-model card gated behind InfoDisclosure in online mode.
      if needsWhisper {
        localRewriteCard
      } else {
        InfoDisclosure("lokales umformen") {
          localRewriteCard
        }
      }
    }
  }

  // MARK: - Whisper (transcription)

  private var whisperCard: some View {
    OnboardingCard(accent: needsWhisper && !appState.selectedLocalModelIsInstalled ? .orange : nil)
    {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          SectionLabel(text: "Whisper (sprache → text)")
          Spacer()
          Button("prüfen") { transcriptionRecheckToken += 1 }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .disabled(appState.isDownloadingLocalModel)
        }

        // Download-in-progress status pill above controls (change 10)
        if appState.isDownloadingLocalModel {
          BlitzStatusPill(state: .download, label: "download läuft — bitte warten")
        }

        if needsWhisper {
          stateRow
          modelPicker
          downloadControls
          if let errorText = appState.localModelDownloadErrorText {
            Text(errorText)
              .font(.system(size: 10.5))
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        } else {
          BlitzStatusPill(state: .online, label: "online Whisper")
          InfoDisclosure("lokale modelle") {
            Text("ein lokales modell brauchst du nur im sicheren lokalen modus.")
          }
        }
      }
    }
  }

  private var needsWhisper: Bool { appState.appSettings.secureLocalModeEnabled }

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
        SectionLabel(text: "optional – nur für lokales umformen")
        InfoDisclosure("wofür") {
          Text(
            "formuliert texte lokal um (E-Mail, Prompt, Social) über den gebündelten llama.cpp-Helper. nur nötig, wenn ein modus offline umformen soll."
          )
        }

        LocalLLMModelPicker(appState: appState)
      }
    }
  }
}
