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
  private var forcedOffline: Bool { appState.appSettings.secureLocalModeEnabled }
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
      if appState.newlyCreatedModeID == modeID {
        showEditor = true
        appState.newlyCreatedModeID = nil
      }
    }
  }

  private var editorContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      nameField
      HotkeyRecorderView(appState: appState, modeID: modeID)

      if isRewriteMode {
        backendPicker

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
        if isRewriteMode {
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
        withAnimation(.easeInOut(duration: 0.16)) {
          if showEditor {
            showEditor = false
          } else {
            showEditor = true
          }
        }
      } label: {
        Image(systemName: showEditor ? "checkmark" : "pencil")
      }
      .buttonStyle(PopoverIconButtonStyle(showEditor ? .primary : .quiet))
      .help(showEditor ? "bearbeitung schließen" : "modus bearbeiten")
      .accessibilityLabel(showEditor ? "Bearbeitung schließen" : "Modus bearbeiten")
      Toggle("aktiv", isOn: bind(\.isEnabled))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .labelsHidden()
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

  // MARK: - Backend

  private var backendPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("verarbeitung")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker(
        "",
        selection: forcedOffline
          ? .constant(RewriteBackend.local) : bind(\.rewrite.rewriteBackend)
      ) {
        ForEach(RewriteBackend.allCases) { backend in
          Text(backend.displayName).tag(backend)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .pickerStyle(.menu)
      .disabled(forcedOffline)

      InfoDisclosure("datenfluss") {
        if forcedOffline {
          Text("sicherer lokaler modus erzwingt lokale verarbeitung.")
        } else if effectiveBackend == .local {
          Text("lokal auf diesem Mac über llama.cpp, ohne cloud.")
        } else {
          Text("text wird zur formulierung an die OpenAI-API gesendet.")
        }
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
