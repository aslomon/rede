import SwiftUI

/// Configurable card for one mode slot: rename, enable, backend, model, prompt, reset.
struct ModeCardView: View {
  @Bindable var appState: AppState
  let type: WorkflowType

  private var config: ModeConfig { appState.modeConfig(for: type) }
  private var forcedOffline: Bool { appState.appSettings.secureLocalModeEnabled }
  private var effectiveBackend: RewriteBackend { appState.resolvedRewriteBackend(for: type) }

  /// The slots that run a rewrite step — only these expose the Memory-context toggle.
  private var isRewriteMode: Bool {
    type == .textImprover || type == .dampfAblassen || type == .emojiText
  }

  /// Memory context is only injected for the text-rewrite modes, not the Emoji/Social mode.
  private var supportsMemoryContext: Bool {
    type == .textImprover || type == .dampfAblassen
  }

  private func bind<V>(_ keyPath: WritableKeyPath<ModeConfig, V>) -> Binding<V> {
    Binding(
      get: { appState.modeConfig(for: type)[keyPath: keyPath] },
      set: { value in appState.updateMode(type) { $0[keyPath: keyPath] = value } }
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
    VStack(alignment: .leading, spacing: 10) {
      header

      nameField
      backendPicker

      if effectiveBackend == .openai {
        modelPicker
      } else if effectiveBackend == .local {
        LocalLLMModelPicker(appState: appState)
      }

      if type == .emojiText {
        emojiDensityPicker
      } else {
        if type == .textImprover {
          tonePicker
        }
        systemPromptEditor
        if type == .textImprover {
          contextField
          replyContextPicker
        }
      }

      if supportsMemoryContext {
        memoryToggle
      }

      footer
    }
    .padding(12)
    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
    )
    .opacity(config.isEnabled ? 1 : 0.6)
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Image(systemName: type.icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(appState.displayName(for: type).uppercased())
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      Text(type.hotkeyLabel)
        .font(.system(size: 9.5, design: .monospaced))
        .foregroundStyle(.quaternary)
      Spacer()
      Toggle("Aktiv", isOn: bind(\.isEnabled))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .labelsHidden()
    }
  }

  // MARK: - Name

  private var nameField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Name")
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
      Text("Verarbeitung")
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

      if forcedOffline {
        Text("Sicherer lokaler Modus erzwingt lokale Verarbeitung.")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      } else if effectiveBackend == .local {
        Text(
          "Lokal auf diesem Mac über Ollama, ohne Cloud. Ollama muss laufen (Modell unten wählen)."
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
      } else {
        Text("Text wird zur Formulierung an die OpenAI-API gesendet.")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Model

  private var modelPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Modell")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer()
        Button(appState.isLoadingModels ? "Lädt …" : "Modelle vom Account laden") {
          appState.loadAvailableModels()
        }
        .font(.system(size: 10, weight: .medium))
        .buttonStyle(SubtleButtonStyle())
        .foregroundStyle(.blue)
        .disabled(appState.isLoadingModels)
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

  // MARK: - Tone / Prompt / Context / Reply

  private var tonePicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Schreibstil (nur ohne eigene Anweisung)")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker("", selection: bind(\.rewrite.tone)) {
        ForEach(TextImprovementSettings.TextTone.allCases) { tone in
          Text(tone.displayName).tag(tone)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  private var systemPromptEditor: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Eigene Anweisung")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      TextEditor(text: bind(\.rewrite.systemPrompt))
        .font(.system(size: 11))
        .frame(height: 96)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6).strokeBorder(
            Color.primary.opacity(0.06), lineWidth: 0.5))
    }
  }

  private var contextField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Kontext (nur ohne eigene Anweisung)")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      TextField("z.B. \"E-Mails im Bereich Unternehmensberatung\"", text: bind(\.rewrite.context))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
    }
  }

  private var replyContextPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Markierten Text einbeziehen")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker("", selection: bind(\.rewrite.replyContextMode)) {
        ForEach(ReplyContextMode.allCases) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .pickerStyle(.menu)
      if config.rewrite.replyContextMode != .off {
        Text(
          "Liest die aktuelle Auswahl in der App und bezieht sie als Kontext ein. Bei OpenAI-Verarbeitung wird der markierte Text mitgesendet."
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var emojiDensityPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Emoji-Dichte")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker("", selection: bind(\.rewrite.emojiDensity)) {
        ForEach(EmojiTextSettings.EmojiDensity.allCases) { density in
          Text(density.displayName).tag(density)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  // MARK: - Memory context (rewrite modes only)

  private var memoryToggle: some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle("Memory-Kontext nutzen", isOn: bind(\.rewrite.useMemoryContext))
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11))
        .disabled(!appState.isMemoryContextEnabled)

      if !appState.isMemoryContextEnabled {
        Text("Zuerst global „Memory als Kontext nutzen“ im Archiv aktivieren.")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      } else if config.rewrite.useMemoryContext {
        if effectiveBackend == .openai {
          Text(
            "Dein persönliches Vokabular (Namen, Fachbegriffe, Fremdwörter) wird als "
              + "Schreibhinweis mitgesendet — bei dieser Online-Verarbeitung an die OpenAI-API."
          )
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("Dein persönliches Vokabular fließt als Schreibhinweis ein — lokal auf dem Gerät.")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Spacer()
      Button("Auf Standard zurücksetzen") {
        appState.resetMode(type)
      }
      .font(.system(size: 10, weight: .medium))
      .buttonStyle(SubtleButtonStyle())
      .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Local LLM model picker (Ollama)

/// Shared control for picking the local rewrite model served by Ollama, with a live reachability
/// status line and a one-line install hint. The selected model is global (like the WhisperKit
/// transcription model), so this binds straight to `appSettings.selectedLocalLLMModelName`.
struct LocalLLMModelPicker: View {
  @Bindable var appState: AppState

  @State private var isReachable: Bool?
  @State private var installedModels: [String] = []

  private var pickerModels: [String] {
    var names = OllamaService.pickerModelNames(installed: installedModels)
    // Keep a persisted-but-unlisted choice selectable so the picker never loses the selection.
    let selected = appState.appSettings.selectedLocalLLMModelName
    if !names.contains(selected), !selected.isEmpty {
      names.append(selected)
    }
    return names
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Lokales Modell (Ollama)")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      Picker("", selection: $appState.appSettings.selectedLocalLLMModelName) {
        ForEach(pickerModels, id: \.self) { name in
          Text(name).tag(name)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .pickerStyle(.menu)

      statusLine

      Text("Ollama installieren (ollama.com), starten und ein Modell laden: `ollama pull gemma3`.")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .task {
      await refreshStatus()
    }
  }

  private var statusLine: some View {
    HStack(spacing: 6) {
      Image(
        systemName: (isReachable ?? false)
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle((isReachable ?? false) ? .green : .orange)

      Text(statusText)
        .font(.system(size: 10))
        .foregroundStyle((isReachable ?? false) ? .green : .orange)

      Spacer()

      Button("Prüfen") {
        Task { await refreshStatus() }
      }
      .font(.system(size: 10, weight: .medium))
      .buttonStyle(SubtleButtonStyle())
      .foregroundStyle(.blue)
    }
  }

  private var statusText: String {
    switch isReachable {
    case .some(true): return "Ollama läuft"
    case .some(false): return "Ollama nicht erreichbar"
    case .none: return "Ollama wird geprüft …"
    }
  }

  private func refreshStatus() async {
    let reachable = await OllamaService.statusCheck()
    let models = reachable ? await OllamaService.installedModels() : []
    isReachable = reachable
    installedModels = models
  }
}
