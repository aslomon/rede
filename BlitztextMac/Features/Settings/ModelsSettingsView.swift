import SwiftUI

/// Tab "modelle": the engines that power rede as a FLAT card list — processing choice, the OpenAI
/// key, the local Whisper transcription engine and the local llama.cpp rewrite model. Status pills
/// live in the card headers (DESIGN.md); the card not matching the chosen processing path is
/// dimmed but stays configurable (e.g. to enter the OpenAI key ahead of time). Memory, vocabulary
/// and learned terms live in the Vokabular tab.
struct ModelsSettingsView: View {
  @Bindable var appState: AppState
  /// Reserved for cross-tab navigation from empty-state CTAs (kept for parity with Prompts tab).
  let selectTab: (Int) -> Void

  /// Bumped by the "prüfen" header action to force a fresh disk read of the installed WhisperKit
  /// models. The disk scan is synchronous, so re-reading inside a recomputed `body` reflects reality.
  @State private var transcriptionRecheckToken = 0

  private var isLocal: Bool { appState.appSettings.secureLocalModeEnabled }

  private var installedLocalModels: [LocalTranscriptionModel] {
    _ = transcriptionRecheckToken
    return LocalTranscriptionService.installedModels()
  }

  private var localModelOptions: [LocalTranscriptionModel] {
    _ = transcriptionRecheckToken
    return LocalTranscriptionService.modelOptions()
  }

  /// Honest one-liner about the selected Whisper model: confirms it is on disk and how many models
  /// total are installed, or states the exact download size still pending for the selection.
  private var transcriptionStateText: String {
    let name = appState.selectedLocalModelDisplayName
    if appState.selectedLocalModelIsInstalled {
      let count = installedLocalModels.count
      return count == 1
        ? "\u{201E}\(name)\u{201C} ist geladen (1 Whisper-Modell auf diesem Mac)."
        : "\u{201E}\(name)\u{201C} ist geladen (\(count) Whisper-Modelle auf diesem Mac)."
    }
    if let size = LocalTranscriptionModel.sizeLabel(for: appState.selectedLocalModelName) {
      return
        "\u{201E}\(name)\u{201C} ist nicht geladen \u{2014} \(size). wird beim laden lokal gespeichert."
    }
    return "\u{201E}\(name)\u{201C} ist nicht geladen. wird beim laden lokal gespeichert."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      processingCard

      // The card not matching the chosen processing path is dimmed so the active choice is
      // obvious — still interactive on purpose.
      openAICard
        .opacity(isLocal ? 0.45 : 1)

      whisperCard
        .opacity(isLocal ? 1 : 0.45)

      // Never dimmed: the local rewrite model powers per-mode "lokal" rewriting in BOTH
      // processing paths (a mode can rewrite locally while transcription runs online).
      localLLMCard
    }
    .padding(16)
    .animation(.easeInOut(duration: 0.2), value: isLocal)
  }

  // MARK: - Processing mode (online OpenAI vs. secure local)

  private var processingCard: some View {
    SettingsSection("verarbeitung", icon: "cpu") {
      Picker("", selection: $appState.appSettings.secureLocalModeEnabled) {
        Text("online · OpenAI").tag(false)
        Text("lokal · sicher").tag(true)
      }
      .pickerStyle(.segmented)
      .controlSize(.small)
      .labelsHidden()
      .onChange(of: appState.appSettings.secureLocalModeEnabled) { _, newValue in
        if newValue && !appState.selectedLocalModelIsInstalled {
          appState.installSelectedLocalModel()
        }
      }
      // Data-flow note stays permanently visible (DESIGN.md: sensible Hinweise als Caption).
      Text(
        isLocal
          ? "alles bleibt auf deinem Mac: Whisper + lokales llama.cpp-Modell. keine online-dienste."
          : "nutzt die OpenAI-API mit deinem eigenen key. leistungsfähiger, aber audio/text gehen online."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - OpenAI key

  private var openAICard: some View {
    OpenAIKeySection(appState: appState, showsStatusPill: true)
      .settingsGroupBackground()
  }

  // MARK: - Lokale Transkription (Whisper)

  private var whisperCard: some View {
    SettingsSection(
      "lokale transkription (Whisper)",
      icon: "waveform",
      action: appState.isDownloadingLocalModel
        ? nil : (label: "prüfen", perform: { transcriptionRecheckToken += 1 }),
      trailing: {
        BlitzStatusPill(
          state: appState.hasAnyTranscriptionEngine ? .local : .download,
          label: appState.hasAnyTranscriptionEngine ? "Whisper lokal" : "Whisper laden"
        )
      }
    ) {
      // Short caption always visible (spec #3)
      Text("lokale sprache-zu-text-engine (WhisperKit). daten bleiben auf dem gerät.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      // Guidance only when no model is installed (spec #3) — the heading carries the concept.
      if !appState.hasAnyTranscriptionEngine {
        EmptyStateCard(
          icon: "waveform",
          title: "kein Whisper-Modell geladen",
          caption:
            "die transkriptions-engine läuft über WhisperKit lokal auf diesem Mac. "
            + "das modell wird auf dem gerät gespeichert. "
            + "lade ein modell, damit rede sprache lokal in text umwandeln kann.",
          accent: .blue,
          buttonLabel: "modell laden",
          action: { appState.installSelectedLocalModel() }
        )
      }

      transcriptionStateRow
      transcriptionModelPicker
      transcriptionDownloadControls
      manageAllModelsButton

      if appState.localModelPreparing && !appState.isDownloadingLocalModel {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text("modell wird vorbereitet … beim ersten mal kann das einige minuten dauern.")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let errorText = appState.localModelDownloadErrorText {
        Text(errorText)
          .font(.system(size: 10.5))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// Bridge from the compact Modelle tab to the full "lokale modelle" window, where every local model
  /// type (Whisper, llama.cpp LLM, embedding) can be loaded, re-downloaded and deleted in one place.
  private var manageAllModelsButton: some View {
    Button {
      NotificationCenter.default.post(name: .openLocalModelsWindow, object: nil)
    } label: {
      Label("alle lokalen modelle verwalten", systemImage: "square.stack.3d.up")
    }
    .buttonStyle(PopoverActionButtonStyle(.secondary))
  }

  private var transcriptionStateRow: some View {
    HStack(spacing: 6) {
      Image(
        systemName: appState.selectedLocalModelIsInstalled
          ? "checkmark.circle.fill" : "arrow.down.circle.fill"
      )
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(appState.selectedLocalModelIsInstalled ? .green : .blue)
      Text(transcriptionStateText)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
  }

  private var transcriptionModelPicker: some View {
    HStack(spacing: 8) {
      Text("Whisper-Modell")
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
  private var transcriptionDownloadControls: some View {
    if let progress = appState.localModelDownloadProgress {
      VStack(alignment: .leading, spacing: 4) {
        ProgressView(value: progress)
        Text(appState.localModelDownloadStatusText ?? "modell wird geladen …")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
    } else {
      HStack(spacing: 10) {
        // Show the install button only when something is actually downloadable. When the model is
        // already installed, the state row above ("… ist geladen") says so — a disabled
        // "… ist geladen" button was a redundant fake button.
        if !appState.selectedLocalModelIsInstalled {
          Button(appState.localModelDownloadButtonTitle) {
            appState.installSelectedLocalModel()
          }
          .buttonStyle(PopoverActionButtonStyle(.primary))
        }

        Link(
          "modellseite",
          destination: LocalTranscriptionService.modelPageURL(
            for: appState.selectedLocalModelName)
        )
        .font(.system(size: 10.5, weight: .medium))
      }
    }
  }

  // MARK: - Lokales Sprachmodell (llama.cpp)

  private var localLLMCard: some View {
    SettingsSection(
      "lokales sprachmodell",
      icon: "text.bubble",
      caption: "formuliert texte lokal um — nutzbar in jedem modus, unabhängig vom online-modus."
    ) {
      LocalLLMModelPicker(appState: appState)
    }
  }
}
