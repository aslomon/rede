import SwiftUI

/// Configurable card for one mode slot: rename, enable, backend, model, prompt, reset.
struct ModeCardView: View {
  @Bindable var appState: AppState
  let type: WorkflowType
  let modeID: ModeConfig.ID

  @Environment(\.colorScheme) private var colorScheme

  /// Progressive disclosure: tone / prompt / context / reply / memory / reset live behind this.
  @State private var showAdvanced = false
  @State private var showEditor = false
  @State var isImprovingPrompt = false
  @State var promptImprovementError: String?

  init(appState: AppState, type: WorkflowType) {
    self.appState = appState
    self.type = type
    self.modeID = type.rawValue
  }

  init(appState: AppState, config: ModeConfig) {
    self.appState = appState
    self.type = config.slot
    self.modeID = config.id
  }

  var config: ModeConfig { appState.modeConfig(for: modeID) ?? appState.modeConfig(for: type) }
  private var isLocalProcessing: Bool { appState.appSettings.secureLocalModeEnabled }
  var effectiveBackend: RewriteBackend { appState.resolvedRewriteBackend(for: config) }

  /// Mirrors `ModeConfig.isAdvancedNonDefault` for the live config — drives the "angepasst" dot.
  private var isAdvancedNonDefault: Bool { config.isAdvancedNonDefault }

  /// The slots that run a rewrite step — only these expose the Memory-context toggle.
  var isRewriteMode: Bool {
    type == .textImprover || type == .dampfAblassen || type == .emojiText
  }

  /// Memory context is only injected for the text-rewrite modes, not the Emoji/Social mode.
  var supportsMemoryContext: Bool {
    type == .textImprover || type == .dampfAblassen
  }

  var supportsAutomaticFieldContext: Bool {
    type == .textImprover || type == .dampfAblassen
  }

  var canEditMode: Bool {
    !isRewriteMode || appState.hasActiveRewriteEngine
  }

  func bind<V>(_ keyPath: WritableKeyPath<ModeConfig, V>) -> Binding<V> {
    Binding(
      get: { config[keyPath: keyPath] },
      set: { value in appState.updateMode(id: modeID) { $0[keyPath: keyPath] = value } }
    )
  }

  private var modelOptions: [RewriteModelOption] {
    var options = RewriteModelRegistry.options(includingFetched: appState.availableModelIDs)
    if !options.contains(where: { $0.id == config.rewrite.modelID }) {
      options.append(RewriteModelRegistry.option(for: config.rewrite.modelID))
    }
    return options
  }

  var body: some View {
    // One unified settings card (same surface as every other section): header row inside the
    // card — the earlier GroupBox(label:) floated the header above its box.
    VStack(alignment: .leading, spacing: 10) {
      header

      // Opacity applied to body only — header remains fully legible when mode is disabled (WCAG 4.5:1)
      Group {
        if showEditor {
          editorContent
        } else {
          summaryContent
        }
      }
      .opacity(config.isEnabled ? 1 : 0.78)
    }
    .settingsGroupBackground()
    .onAppear {
      // A freshly created mode opens straight into its editor so the user can rename/configure it.
      if appState.newlyCreatedModeID == modeID, canEditMode {
        showEditor = true
        appState.newlyCreatedModeID = nil
      }
    }
    .onChange(of: appState.hasActiveRewriteEngine) { _, hasEngine in
      if isRewriteMode && !hasEngine {
        withAnimation(.easeInOut(duration: 0.16)) { showEditor = false }
      }
    }
  }

  private var editorContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      nameField
      HotkeyRecorderView(appState: appState, modeID: modeID)

      if isRewriteMode {
        processingRouteSummary

        if effectiveBackend == .openai {
          modelPicker
        } else if effectiveBackend == .local {
          LocalLLMModelPicker(appState: appState)
        }

        if type == .emojiText {
          emojiDensityPicker
        }

        advancedDisclosure
      }

      editorFooter
    }
  }

  private var summaryContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        if isRewriteMode && !canEditMode {
          BlitzStatusPill(state: .warning, label: "modell fehlt")
        } else if isRewriteMode {
          BlitzStatusPill(
            state: backendPillState, label: effectiveBackend == .local ? "lokal" : "online")
        } else {
          BlitzStatusPill(state: .online, label: "freitext")
        }
        if isAdvancedNonDefault {
          BlitzStatusPill(state: .warning, label: "angepasst")
        }
        Spacer(minLength: 0)
      }

      Text(summaryLine)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      // "Bearbeiten" button removed — pencil icon in header is the sole edit entry point (spec change 7)
    }
  }

  private var backendPillState: BlitzStatusPill.State {
    effectiveBackend == .local ? .local : .online
  }

  private var summaryLine: String {
    if !isRewriteMode {
      return appState.workflowSubtitle(for: config)
    }
    if !canEditMode {
      return isLocalProcessing
        ? "erst lokales LLM laden, dann modus bearbeiten."
        : "erst OpenAI-Key verbinden, dann modus bearbeiten."
    }
    if type == .emojiText {
      return "emoji-dichte: \(config.rewrite.emojiDensity.displayName)."
    }
    if effectiveBackend == .local {
      return "umformung läuft lokal über llama.cpp."
    }
    return "umformung über \(config.rewrite.modelID)."
  }

  private var editorFooter: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider().opacity(0.4)
      footerRow
    }
  }

  private var footerRow: some View {
    HStack {
      moveControls
      Spacer()
      Button {
        appState.resetMode(id: modeID)
      } label: {
        Label("zurücksetzen", systemImage: "arrow.uturn.backward")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))

      if appState.canDeleteMode(id: modeID) {
        DestructiveClearButton(
          "löschen",
          message: "dieser eigene modus wird dauerhaft aus rede entfernt."
        ) {
          appState.deleteMode(id: modeID)
        }
      }

      Button {
        withAnimation(.easeInOut(duration: 0.16)) { showEditor = false }
      } label: {
        Label("fertig", systemImage: "checkmark")
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
    }
  }

  var moveControls: some View {
    HStack(spacing: 6) {
      Button {
        appState.moveMode(id: modeID, offset: -1)
      } label: {
        Image(systemName: "arrow.up")
      }
      .buttonStyle(PopoverIconButtonStyle(.quiet))
      .disabled(!appState.canMoveMode(id: modeID, offset: -1))
      .help("nach oben")
      .accessibilityLabel("Modus nach oben verschieben")

      Button {
        appState.moveMode(id: modeID, offset: 1)
      } label: {
        Image(systemName: "arrow.down")
      }
      .buttonStyle(PopoverIconButtonStyle(.quiet))
      .disabled(!appState.canMoveMode(id: modeID, offset: 1))
      .help("nach unten")
      .accessibilityLabel("Modus nach unten verschieben")
    }
  }

  // MARK: - Advanced (progressive disclosure)

  // Uses SwiftUI DisclosureGroup for native chevron + animation (spec change 13)
  private var advancedDisclosure: some View {
    DisclosureGroup(isExpanded: $showAdvanced) {
      // DisclosureGroup wraps multiple children in a center-aligned VStack by default, which
      // left-floated wide controls but centered narrow ones (pickers, toggles, segmented).
      // Force leading alignment + full width so every row lines up on the left edge.
      VStack(alignment: .leading, spacing: 10) {
        advancedContent
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 6)
    } label: {
      advancedToggleLabel
    }
    .animation(.easeInOut(duration: 0.15), value: showAdvanced)
  }

  private var advancedToggleLabel: some View {
    HStack(spacing: 6) {
      Text("erweitert")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      // "angepasst" indicator dot enlarged to 7x7 for better visibility (spec change 13)
      if !showAdvanced && isAdvancedNonDefault {
        Circle()
          .fill(Color.orange)
          .frame(width: 7, height: 7)
          .help("angepasst")
      }
    }
  }

  // Ordered per spec change 8:
  //   1. systemPromptEditor
  //   2. disabled-note caption (when hasCustomPrompt)
  //   3. tonePicker (when no custom prompt)
  //   4. contextField
  //   5. replyContextPicker
  //   6. automaticFieldContextToggle
  //   7. unifiedMemoryControls
  //   8. variantChoiceToggle
  // footer computed var removed — inline Divider before editorFooter where needed.
  @ViewBuilder
  private var advancedContent: some View {
    if type == .emojiText {
      systemPromptEditor
      if hasCustomPrompt {
        Text("emoji-dichte ist deaktiviert, solange eine eigene anweisung gesetzt ist.")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      variantChoiceToggle
    } else if isRewriteMode {
      // (1) Custom prompt editor always at top
      systemPromptEditor

      // (2) Disabled note immediately below the editor when a custom prompt is active
      if hasCustomPrompt {
        Text("schreibstil & kontext sind deaktiviert, solange eine eigene anweisung gesetzt ist.")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      // (3) Tone picker only when no custom prompt is set
      if !hasCustomPrompt, type == .textImprover {
        tonePicker
      }

      // (4) Context field
      if type == .textImprover {
        contextField
      }

      // (5) Reply context picker
      if type == .textImprover {
        replyContextPicker
      }

      // (6) Automatic field context toggle
      if supportsAutomaticFieldContext {
        automaticFieldContextToggle
      }

      // (7) Unified memory controls
      if supportsMemoryContext {
        unifiedMemoryControls
      }

      // (8) Variant choice toggle
      variantChoiceToggle
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 8) {
      // Mode icon uses accent colour for per-mode visual identity (spec change 5)
      Image(systemName: type.icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(type.accentColorValue)
      Text(appState.displayName(for: config))
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
      hotkeyKeycaps
      Spacer(minLength: 8)
      // Pencil opens editor; checkmark closes it. Pencil only activates when not already editing (spec change 7)
      Button {
        guard canEditMode else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
          if showEditor {
            showEditor = false
          } else {
            showEditor = true
          }
        }
      } label: {
        Image(systemName: canEditMode ? (showEditor ? "checkmark" : "pencil") : "lock")
      }
      .buttonStyle(PopoverIconButtonStyle(showEditor ? .primary : .quiet))
      .disabled(!canEditMode)
      .help(
        canEditMode
          ? (showEditor ? "bearbeitung schließen" : "modus bearbeiten")
          : (isLocalProcessing ? "erst lokales LLM laden" : "erst OpenAI-Key verbinden"))
      .accessibilityLabel(canEditMode ? "Modus bearbeiten" : "Modus gesperrt")
      Toggle("aktiv", isOn: bind(\.isEnabled))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .labelsHidden()
        .disabled(!canEditMode)
    }
  }

  /// The mode's hotkey as quiet mini keycaps (the old 9.5pt `.quaternary` text was near-invisible).
  /// Hidden entirely while no combination is configured — the editor is the place to set one.
  @ViewBuilder
  private var hotkeyKeycaps: some View {
    let hotkey = appState.hotkeyConfig(for: modeID)
    if hotkey.isConfigured && hotkey.isEnabled {
      HStack(spacing: 3) {
        ForEach(Array(hotkey.labelParts.enumerated()), id: \.offset) { _, part in
          Text(part)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .liquidGlassKeycap()
        }
      }
      .fixedSize()
      .accessibilityHidden(true)
    }
  }

  // MARK: - Name

  private var nameField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("name")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      TextField(ModeConfig.defaultUserName(for: type), text: bind(\.userName))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
    }
  }

  // MARK: - Processing route

  private var processingRouteSummary: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("verarbeitung")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      HStack(spacing: 6) {
        BlitzStatusPill(state: isLocalProcessing ? .local : .online, label: isLocalProcessing ? "lokal" : "online")
        Text(isLocalProcessing ? "global: Whisper + llama.cpp" : "global: OpenAI Whisper + OpenAI-Modell")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      InfoDisclosure("datenfluss") {
        Text(
          isLocalProcessing
            ? "globale verarbeitung steht auf lokal: diktat läuft über Whisper auf diesem Mac, umformung über llama.cpp."
            : "globale verarbeitung steht auf online: Whisper und umformung laufen über die OpenAI-API."
        )
      }
    }
  }

  // MARK: - Model

  private var modelPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("modell")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer()
        // Fetch the account's OpenAI model list on demand. Compact pill keeps the redesigned
        // look while preserving the original "Modelle vom Account laden" capability; errors
        // surface in the modelLoadError caption below.
        if appState.availableModelIDs.isEmpty {
          Button {
            appState.loadAvailableModels()
          } label: {
            BlitzStatusPill(
              state: .warning, label: appState.isLoadingModels ? "lädt …" : "modelle laden")
          }
          .buttonStyle(.plain)
          .disabled(appState.isLoadingModels)
        }
      }
      Picker("", selection: bind(\.rewrite.modelID)) {
        ForEach(modelOptions) { option in
          Text(option.menuLabel).tag(option.id)
        }
      }
      .labelsHidden()
      .controlSize(.small)

      if let error = appState.modelLoadError {
        Text(error)
          .font(.system(size: 10))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// Tone + context only take effect when no custom prompt is set (see
  /// `LLMService.rewriteSystemPrompt`); mirror the `forcedOffline` disabled pattern.
  var hasCustomPrompt: Bool { !config.rewrite.systemPrompt.isEmpty }
}

// MARK: - Local LLM model picker (llama.cpp)
//
// The redesigned, state-driven `LocalLLMModelPicker` lives in `LocalLLMModelPicker.swift`.
// The advanced-section subviews (tone / prompt / context / reply / emoji / memory / footer)
// live in `ModeCardAdvanced.swift`.
