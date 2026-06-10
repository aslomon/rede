import SwiftUI

/// Tab "Modelle": the engines that power rede \u{2014} "Online" (the OpenAI API key) and "Lokal" (the
/// local Whisper transcription engine, the local llama.cpp rewrite model and the secure-local master
/// switch). Memory, vocabulary and learned terms live in the Vokabular tab.
struct ModelsSettingsView: View {
  @Bindable var appState: AppState
  /// Reserved for cross-tab navigation from empty-state CTAs (kept for parity with Prompts tab).
  let selectTab: (Int) -> Void

  /// Bumped by the "Prüfen" icon button to force a fresh disk read of the installed WhisperKit models.
  /// The disk scan is synchronous, so re-reading inside a recomputed `body` reflects reality.
  @State private var transcriptionRecheckToken = 0

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
        "\u{201E}\(name)\u{201C} ist nicht geladen \u{2014} \(size). Wird beim Installieren lokal gespeichert."
    }
    return "\u{201E}\(name)\u{201C} ist nicht geladen. Wird beim Installieren lokal gespeichert."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      // spec #1: no top-level dual-status HStack \u{2014} pills live in section headers
      modeSelector
      Divider().opacity(0.5)
      // The non-selected processing mode is dimmed so the active choice is obvious (still
      // configurable, e.g. to enter your OpenAI key ahead of time).
      onlineBand
        .opacity(appState.appSettings.secureLocalModeEnabled ? 0.4 : 1)
      Divider().opacity(0.5)
      localBand
        .opacity(appState.appSettings.secureLocalModeEnabled ? 1 : 0.4)
    }
    .padding(16)
    .animation(.easeInOut(duration: 0.2), value: appState.appSettings.secureLocalModeEnabled)
  }

  // MARK: - Processing mode (Online OpenAI vs. secure local)
  // A clear either/or at the top, now that the popover's bottom engine bar is gone. Drives the same
  // secureLocalModeEnabled flag and keeps installing the local model when switching to local.

  private var modeSelector: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Verarbeitung")
      Picker("", selection: $appState.appSettings.secureLocalModeEnabled) {
        Text("Online · OpenAI").tag(false)
        Text("Lokal · Sicher").tag(true)
      }
      .pickerStyle(.segmented)
      .controlSize(.small)
      .labelsHidden()
      .onChange(of: appState.appSettings.secureLocalModeEnabled) { _, newValue in
        if newValue && !appState.selectedLocalModelIsInstalled {
          appState.installSelectedLocalModel()
        }
      }
      Text(
        appState.appSettings.secureLocalModeEnabled
          ? "Alles bleibt auf deinem Mac: Whisper + lokales llama.cpp-Modell. Keine Online-Dienste."
          : "Nutzt die OpenAI-API mit deinem eigenen Key. Leistungsfähiger, aber Audio/Text gehen online."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Online band (OpenAI)
  // spec #1: trailing BlitzStatusPill in section header
  // spec #2: explanatory paragraph removed; moved inside OpenAIKeySection's InfoDisclosure

  private var onlineBand: some View {
    ModelsSectionWithPill(
      "Online",
      pill: BlitzStatusPill(
        state: appState.hasOpenAIKey ? .online : .warning,
        label: appState.hasOpenAIKey ? "Online bereit" : "OpenAI fehlt"
      )
    ) {
      if !appState.hasOpenAIKey {
        SettingsStatusBadge(.warning, label: "OpenAI nicht eingerichtet")
      }
      OpenAIKeySection(appState: appState)
    }
  }

  // MARK: - Local band (Whisper + llama.cpp + secure-local switch)
  // spec #1: trailing BlitzStatusPill in section header
  // spec #4: Whisper first, llama.cpp second, secure-local toggle at the bottom

  private var localBand: some View {
    ModelsSectionWithPill(
      "Lokal",
      pill: BlitzStatusPill(
        state: appState.hasAnyTranscriptionEngine ? .local : .download,
        label: appState.hasAnyTranscriptionEngine ? "Whisper lokal" : "Whisper laden"
      )
    ) {
      localTranscriptionSection
      localLLMSection
    }
  }

  // MARK: - Lokale Transkription (Whisper)
  // spec #3: single caption line always visible; full paragraph only in EmptyStateCard

  private var localTranscriptionSection: some View {
    SettingsSection(
      "Lokale Transkription (Whisper)",
      action: appState.isDownloadingLocalModel
        ? nil : (label: "Prüfen", perform: { transcriptionRecheckToken += 1 })
    ) {
      // Short caption always visible (spec #3)
      Text("Lokale Sprach-zu-Text-Engine (WhisperKit). Daten bleiben auf dem Gerät.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      // Full paragraph only when no model is installed (spec #3)
      if !appState.hasAnyTranscriptionEngine {
        EmptyStateCard(
          icon: "waveform",
          title: "Kein Whisper-Modell geladen",
          caption:
            "Die Transkriptions-Engine läuft über WhisperKit lokal auf diesem Mac. "
            + "Das Modell wird auf dem Gerät gespeichert. "
            + "Lade ein Modell, damit rede Sprache lokal in Text umwandeln kann.",
          accent: .blue,
          buttonLabel: "Modell laden",
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
          Text("Modell wird vorbereitet … beim ersten Mal kann das einige Minuten dauern.")
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

  /// Bridge from the compact Modelle tab to the full "Lokale Modelle" window, where every local model
  /// type (Whisper, llama.cpp LLM, embedding) can be loaded, re-downloaded and deleted in one place.
  private var manageAllModelsButton: some View {
    Button {
      NotificationCenter.default.post(name: .openLocalModelsWindow, object: nil)
    } label: {
      Label("Alle lokalen Modelle verwalten", systemImage: "square.stack.3d.up")
        .font(.system(size: 10.5, weight: .medium))
    }
    .buttonStyle(PopoverActionButtonStyle(.secondary))
    .controlSize(.small)
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
        Text(appState.localModelDownloadStatusText ?? "Modell wird geladen...")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
    } else {
      HStack(spacing: 10) {
        // Show the install button only when something is actually downloadable. When the model is
        // already installed, the state row above ("… ist geladen") says so — a disabled
        // "… ist installiert" button was a redundant fake button.
        if !appState.selectedLocalModelIsInstalled {
          Button(appState.localModelDownloadButtonTitle) {
            appState.installSelectedLocalModel()
          }
          .controlSize(.small)
          .buttonStyle(PopoverActionButtonStyle(.primary))
        }

        Link(
          "Modellseite",
          destination: LocalTranscriptionService.modelPageURL(
            for: appState.selectedLocalModelName)
        )
        .font(.system(size: 10.5, weight: .medium))
      }
    }
  }

  // MARK: - Lokales Sprachmodell (llama.cpp)

  private var localLLMSection: some View {
    SettingsSection("Lokales Sprachmodell") {
      LocalLLMModelPicker(appState: appState)
    }
  }
}

// MARK: - ModelsSectionWithPill
//
// A GroupBox variant with a trailing BlitzStatusPill in the label row.
// Lives here (not in frozen SettingsPrimitives.swift) and is file-private to this module.
// Uses the same visual rhythm as SettingsSection from SettingsPrimitives.

private struct ModelsSectionWithPill<Pill: View, Content: View>: View {
  let label: String
  let pill: Pill
  @ViewBuilder let content: Content

  init(
    _ label: String,
    pill: Pill,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.pill = pill
    self.content = content()
  }

  var body: some View {
    // Plain group header (label + pill). The inner SettingsSection children are themselves the
    // cards now (heading inside), so wrapping the band in its own background produced a visible
    // box-in-box. One container level only.
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        SectionLabel(text: label)
        Spacer()
        pill
      }
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
