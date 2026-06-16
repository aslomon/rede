import SwiftUI

/// Tab "modelle": the engines that power rede as a FLAT card list — processing choice, the OpenAI
/// key, the local Whisper transcription engine and the local llama.cpp rewrite model. Models that
/// are already on disk show as directly selectable rows (one tap = active); downloading more lives
/// behind a disclosure so the card stays calm. Status pills live in the card headers (DESIGN.md);
/// only the cards matching the chosen processing path are visible.
struct ModelsSettingsView: View {
  @Bindable var appState: AppState
  /// Reserved for cross-tab navigation from empty-state CTAs (kept for parity with Modi tab).
  let selectTab: (Int) -> Void

  /// Bumped by the "prüfen" header action to force a fresh disk read of the installed WhisperKit
  /// models. The disk scan is synchronous, so re-reading inside a recomputed `body` reflects reality.
  @State private var transcriptionRecheckToken = 0
  /// The download picker's choice among the NOT-installed Whisper models. Separate from the
  /// active-model selection so browsing downloads never flips the engine in use.
  @State private var whisperDownloadTarget = ""
  /// Collapses the download row behind a quiet "+" button while installed models exist, so the
  /// card reads as "your models" first.
  @State private var showWhisperDownloadRow = false

  private var isLocal: Bool { appState.appSettings.secureLocalModeEnabled }

  private var installedWhisperModels: [LocalTranscriptionModel] {
    _ = transcriptionRecheckToken
    return LocalTranscriptionService.installedModels()
  }

  private var notInstalledWhisperModels: [LocalTranscriptionModel] {
    _ = transcriptionRecheckToken
    return LocalTranscriptionService.modelOptions().filter { !$0.isInstalled }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      processingCard

      if isLocal {
        whisperCard
        localLLMCard
      } else {
        openAICard
      }
    }
    .padding(16)
    .animation(.easeInOut(duration: 0.2), value: isLocal)
    .task {
      await appState.localModelManager.refresh()
      // Downloaded models should be selected/usable without a manual pick.
      appState.adoptInstalledLocalModelsIfNeeded()
    }
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
        RedeStatusPill(
          state: installedWhisperModels.isEmpty ? .download : .local,
          label: installedWhisperModels.isEmpty ? "Whisper laden" : "Whisper lokal"
        )
      }
    ) {
      if installedWhisperModels.isEmpty {
        EmptyStateCard(
          icon: "waveform",
          title: "kein Whisper-Modell geladen",
          caption:
            "lade ein modell, damit rede sprache lokal in text umwandeln kann — "
            + "es wird einmalig geladen und bleibt auf diesem Mac.",
          accent: .blue
        )
        if !appState.isDownloadingLocalModel {
          whisperDownloadRow
        }
      } else {
        // Installed models are directly selectable (downloaded ⇒ one tap from active).
        ForEach(installedWhisperModels) { model in
          ModelSelectRow(
            title: model.displayName,
            subtitle: model.sizeLabel.map { "lokal · \($0)" } ?? "lokal",
            isActive: appState.selectedLocalModelName == model.id,
            select: { appState.appSettings.selectedLocalTranscriptionModelName = model.id }
          )
        }

        // Further downloads stay tucked away so the card reads as "your models" first.
        // (Not InfoDisclosure — that styles its content as secondary text, wrong for controls.)
        if !notInstalledWhisperModels.isEmpty, !appState.isDownloadingLocalModel {
          if showWhisperDownloadRow {
            whisperDownloadRow
          } else {
            Button {
              withAnimation(.easeInOut(duration: 0.15)) { showWhisperDownloadRow = true }
            } label: {
              Label("weiteres modell laden …", systemImage: "plus")
            }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
          }
        }
      }

      if let progress = appState.localModelDownloadProgress {
        VStack(alignment: .leading, spacing: 4) {
          ProgressView(value: progress)
          Text(appState.localModelDownloadStatusText ?? "modell wird geladen …")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
      }

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

      manageAllModelsButton
    }
  }

  /// One compact row: pick a not-yet-installed Whisper model and load it. Loading also makes it
  /// the active model (`installLocalModel(named:)` selects on success).
  private var whisperDownloadRow: some View {
    HStack(spacing: 8) {
      Picker("", selection: downloadTargetBinding) {
        ForEach(notInstalledWhisperModels) { model in
          Text(downloadOptionLabel(model)).tag(model.id)
        }
      }
      .labelsHidden()
      .controlSize(.small)

      Button {
        appState.installLocalModel(named: downloadTargetBinding.wrappedValue)
      } label: {
        Label("laden", systemImage: "arrow.down.circle.fill")
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
      .disabled(notInstalledWhisperModels.isEmpty)
    }
  }

  /// Keeps the download choice valid as models get installed: falls back to the first
  /// not-installed option whenever the stored target is gone (installed or unknown).
  private var downloadTargetBinding: Binding<String> {
    Binding(
      get: {
        let options = notInstalledWhisperModels
        if options.contains(where: { $0.id == whisperDownloadTarget }) {
          return whisperDownloadTarget
        }
        return options.first?.id ?? ""
      },
      set: { whisperDownloadTarget = $0 }
    )
  }

  private func downloadOptionLabel(_ model: LocalTranscriptionModel) -> String {
    if let size = model.sizeLabel { return "\(model.displayName) · \(size)" }
    return model.displayName
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

  // MARK: - Lokales Sprachmodell (llama.cpp)

  private var localLLMCard: some View {
    SettingsSection(
      "lokales sprachmodell",
      icon: "text.bubble",
      caption: "formuliert texte lokal um — nur aktiv, wenn verarbeitung auf lokal steht.",
      trailing: { llmStatusPill }
    ) {
      // The section header above carries the status pill; the picker renders only the rows.
      LocalLLMModelPicker(appState: appState)
    }
  }

  private var llmStatusPill: RedeStatusPill {
    let manager = appState.localModelManager
    let selection = appState.appSettings.selectedLocalLLM
    if selection.isConfigured, manager.installedLlamaCppModel(for: selection.modelID) != nil {
      return RedeStatusPill(state: .ready, label: "gewählt")
    }
    if manager.llamaCppInstalled.isEmpty {
      return RedeStatusPill(state: .download, label: "laden")
    }
    return RedeStatusPill(state: .warning, label: "auswählen")
  }
}
