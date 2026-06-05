import SwiftUI

// MARK: - Root router

struct MenuBarView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      switch appState.page {
      case .main:
        MainPageView(appState: appState)
      case .settings:
        SettingsPageView(appState: appState)
      case .workflow:
        WorkflowPageView(appState: appState)
      }
    }
    // The SwiftUI root width IS the popover width (it overrides NSPopover.contentSize). 410 to match.
    .frame(width: 410)
    // Opaque backstop: fixes dark-mode transparency wash-out (macOS 26 glass / <26 material).
    .blitztextSurface()
    .animation(.easeInOut(duration: 0.2), value: appState.page)
  }
}

// MARK: - Main Page

private struct MainPageView: View {
  @Bindable var appState: AppState
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      headerBand
      Divider()

      if BlitztextInstallLocationService.shouldOfferMoveToApplications {
        installHintBanner
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 6)
      }

      enginePanel
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, appState.accessibilityPermissionGranted ? 6 : 4)

      if !appState.accessibilityPermissionGranted {
        accessibilityHintBanner
          .padding(.horizontal, 16)
          .padding(.bottom, 6)
      }

      workflowList
        .padding(.vertical, 2)

      appFooter
    }
  }

  // MARK: Header

  private var headerBand: some View {
    VStack(spacing: 0) {
      HStack {
        HStack(spacing: 6) {
          Text("Blitztext")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)

          Text("macOS Preview")
            .font(.system(size: 9.5, weight: .medium))
            // Was .quaternary — too low contrast in dark mode; .secondary reads at 4.5:1
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button {
          appState.page = .settings
        } label: {
          ZStack(alignment: .topTrailing) {
            Image(systemName: "gear")
              .font(.system(size: 13, weight: .medium))
              // Was .tertiary — raised to .secondary for legibility in dark mode
              .foregroundStyle(.secondary)
              .frame(width: 28, height: 28)
              .background(
                RoundedRectangle(cornerRadius: 6)
                  .fill(Color.primary.opacity(0.00001))  // hit target only
              )
              .contentShape(Rectangle())

            if !appState.accessibilityPermissionGranted {
              Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .offset(x: -4, y: 4)
            }
          }
        }
        .buttonStyle(SubtleButtonStyle())
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 8)

      if appState.isConfigured {
        configuredStatusLine
      } else {
        unconfiguredStatusLine
      }
    }
    .padding(.bottom, 12)
    // colorScheme-aware header band — no more forced 0.5 alpha that washes out in dark mode
    .background(MenuBarTokens.headerBand(colorScheme: colorScheme))
  }

  private var configuredStatusLine: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(.green)
        .frame(width: 7, height: 7)
      Text("Bereit")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)
    }
  }

  private var unconfiguredStatusLine: some View {
    VStack(spacing: 10) {
      ZStack {
        Circle()
          // Was hardcoded Color.orange.opacity(0.1) — now colorScheme-aware
          .fill(MenuBarTokens.tintFill(.orange, colorScheme: colorScheme))
          .frame(width: 40, height: 40)
        Image(systemName: "key.fill")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.orange)
      }

      VStack(spacing: 4) {
        Text("Einrichtung nötig")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.primary)

        Text(
          "Starte die geführte Einrichtung, um Blitztext in wenigen Schritten startklar zu machen."
        )
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
      }

      Button {
        NotificationCenter.default.post(name: .openOnboardingWindow, object: nil)
      } label: {
        Text("Blitztext einrichten")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.primary)
          .padding(.horizontal, 20)
          .padding(.vertical, 7)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(MenuBarTokens.cardStroke(colorScheme: colorScheme), lineWidth: 0.5)
          )
      }
      .buttonStyle(SubtleButtonStyle())
    }
  }

  // MARK: Engine Panel

  /// Replaces the bare Toggle with a 2-segment Picker + status line for clarity.
  private var enginePanel: some View {
    let modelOptions = LocalTranscriptionService.modelOptions()
    let selectedModelInstalled = appState.selectedLocalModelIsInstalled

    return VStack(alignment: .leading, spacing: 8) {
      // Engine selector row
      HStack(spacing: 8) {
        Text("Transkription")
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(.secondary)

        Picker(
          "",
          selection: Binding(
            get: { appState.appSettings.secureLocalModeEnabled },
            set: { newValue in
              if newValue {
                appState.enableSecureLocalMode()
              } else {
                appState.appSettings.secureLocalModeEnabled = false
              }
            }
          )
        ) {
          Text("Online").tag(false)
          Text("Lokal").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .disabled(appState.isDownloadingLocalModel)
        .frame(maxWidth: .infinity)
      }

      // Status line: accent dot + engine name
      engineStatusLine

      // Local-mode extras
      if appState.appSettings.secureLocalModeEnabled {
        HStack(spacing: 8) {
          Text("Modell")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)

          Picker(
            "",
            selection: Binding(
              get: { appState.selectedLocalModelName },
              set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
            )
          ) {
            ForEach(modelOptions) { model in
              Text(menuBarModelLabel(for: model)).tag(model.id)
            }
          }
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .controlSize(.small)
          .disabled(appState.isDownloadingLocalModel)
        }

        if let progress = appState.localModelDownloadProgress {
          VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
            Text(appState.localModelDownloadStatusText ?? "Modell wird geladen…")
              .font(.system(size: 10.5))
              .foregroundStyle(.secondary)
          }
        } else if !selectedModelInstalled {
          Button(appState.localModelDownloadButtonTitle) {
            appState.installSelectedLocalModel()
          }
          .controlSize(.small)
        }

        if let errorText = appState.localModelDownloadErrorText {
          Text(errorText)
            .font(.system(size: 10.5))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        // Was Color.primary.opacity(0.035) — invisible in dark mode; now colorScheme-aware
        .fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(MenuBarTokens.cardStroke(colorScheme: colorScheme), lineWidth: 0.5)
    )
  }

  private var engineStatusLine: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(appState.appSettings.secureLocalModeEnabled ? Color.green : Color.blue)
        .frame(width: 6, height: 6)

      Text(engineStatusText)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var engineStatusText: String {
    if appState.appSettings.secureLocalModeEnabled {
      if appState.isDownloadingLocalModel {
        return appState.localModelDownloadStatusText ?? "Lokales Modell wird geladen."
      }
      if appState.selectedLocalModelIsInstalled {
        return "Lokal mit \(appState.selectedLocalModelDisplayName)."
      }
      return "\(appState.selectedLocalModelDisplayName) ist noch nicht installiert."
    }
    return "Online via OpenAI Whisper."
  }

  private func menuBarModelLabel(for model: LocalTranscriptionModel) -> String {
    if model.isInstalled {
      return "\(model.shortDisplayName) · geladen"
    }
    if let size = model.sizeLabel {
      return "\(model.shortDisplayName) · nicht geladen (\(size))"
    }
    return "\(model.shortDisplayName) · nicht geladen"
  }

  // MARK: Banners

  private var accessibilityHintBanner: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "hand.raised.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.orange)
        .frame(width: 18, height: 18)

      VStack(alignment: .leading, spacing: 3) {
        Text("Einfügen braucht Bedienungshilfen.")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)

        Text("Nach Updates kann macOS die Freigabe neu verlangen.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      Button("Öffnen") {
        appState.requestAccessibilityPermission()
      }
      .font(.system(size: 10.5, weight: .medium))
      .buttonStyle(SubtleButtonStyle())
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        // Was hardcoded Color.orange.opacity(0.08) — too faint in dark mode
        .fill(MenuBarTokens.tintFill(.orange, colorScheme: colorScheme))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(MenuBarTokens.tintStroke(.orange, colorScheme: colorScheme), lineWidth: 0.5)
    )
  }

  private var installHintBanner: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "externaldrive.badge.plus")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.orange)
        .frame(width: 18, height: 18)

      VStack(alignment: .leading, spacing: 3) {
        Text("Für sauberen Anmeldestart nach /Applications verschieben.")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)

        Text("Sonst entstehen leichter doppelte Login-Items oder uneinheitliche Updates.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      Button("Prüfen") {
        appState.page = .settings
      }
      .font(.system(size: 10.5, weight: .medium))
      .buttonStyle(SubtleButtonStyle())
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(MenuBarTokens.tintFill(.orange, colorScheme: colorScheme))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(MenuBarTokens.tintStroke(.orange, colorScheme: colorScheme), lineWidth: 0.5)
    )
  }

  // MARK: Workflow list

  private var workflowList: some View {
    VStack(spacing: 0) {
      ForEach(WorkflowType.mainMenuCases) { type in
        let enabled = appState.isWorkflowAvailable(type)
        WorkflowRowView(
          type: type,
          enabled: enabled,
          customName: appState.displayName(for: type),
          subtitle: appState.workflowSubtitle(for: type)
        ) {
          appState.startWorkflowFromPopover(type)
        }
      }
    }
  }
}

// MARK: - Settings Page

private struct SettingsPageView: View {
  @Bindable var appState: AppState
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          appState.page = .main
        } label: {
          HStack(spacing: 3) {
            Image(systemName: "chevron.left")
              .font(.system(size: 10, weight: .semibold))
            Text("Zurück")
              .font(.system(size: 12))
          }
          .foregroundStyle(.secondary)
        }
        .buttonStyle(SubtleButtonStyle())

        Spacer()

        Text("Einstellungen")
          .font(.system(size: 12, weight: .semibold))

        Spacer()
        settingsQuickAction
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(MenuBarTokens.headerBand(colorScheme: colorScheme))

      Divider()

      SettingsContentView(appState: appState)

      Spacer(minLength: 0)

      appFooter
    }
  }

  @ViewBuilder
  private var settingsQuickAction: some View {
    if !appState.accessibilityPermissionGranted {
      Button {
        appState.requestAccessibilityPermission()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "hand.raised")
            .font(.system(size: 10, weight: .semibold))
          Text("Rechte")
            .font(.system(size: 12))
        }
        .foregroundStyle(.orange)
      }
      .buttonStyle(SubtleButtonStyle())
    } else {
      Color.clear.frame(width: 58, height: 18)
    }
  }
}

// MARK: - Workflow Page

private struct WorkflowPageView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      if let workflow = appState.activeWorkflow {
        workflowHeader(workflow: workflow)

        Divider()

        switch workflow.type {
        case .transcription, .localTranscription:
          if let w = workflow as? TranscriptionWorkflow {
            TranscriptionActiveView(workflow: w, copyOnly: appState.lastRunWasCopyOnly)
          }
        case .textImprover:
          if let w = workflow as? TextImprovementWorkflow {
            TextImproverActiveView(
              workflow: w, copyOnly: appState.lastRunWasCopyOnly,
              fallbackNote: appState.lastRewriteFallbackNote)
          }
        case .dampfAblassen:
          if let w = workflow as? DampfAblassenWorkflow {
            DampfAblassenActiveView(
              workflow: w, copyOnly: appState.lastRunWasCopyOnly,
              fallbackNote: appState.lastRewriteFallbackNote)
          }
        case .emojiText:
          if let w = workflow as? EmojiTextWorkflow {
            EmojiTextActiveView(
              workflow: w, copyOnly: appState.lastRunWasCopyOnly,
              fallbackNote: appState.lastRewriteFallbackNote)
          }
        }

        if case .done = workflow.phase, workflow.didTruncateAtMaxDuration {
          truncationBanner
        }

        Spacer(minLength: 0)

        appFooter
      }
    }
  }

  private func workflowHeader(workflow: any Workflow) -> some View {
    HStack {
      Button {
        appState.resetCurrentWorkflow()
      } label: {
        HStack(spacing: 3) {
          Image(systemName: "chevron.left")
            .font(.system(size: 10, weight: .semibold))
          Text("Zurück")
            .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
      }
      .buttonStyle(SubtleButtonStyle())

      Spacer()

      HStack(spacing: 5) {
        Image(systemName: workflow.type.icon)
          .font(.system(size: 11))
          .foregroundStyle(workflow.type.accentColorValue)
        Text(appState.displayName(for: workflow.type))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.primary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  /// Honest note shown after a run whose recording hit the safety cap and was auto-stopped — the
  /// captured part was still transcribed, but the user should know the tail was cut.
  private var truncationBanner: some View {
    let minutes = Int(AudioRecorder.maxRecordingDuration / 60)
    return HStack(alignment: .top, spacing: 6) {
      Image(systemName: "clock.badge.exclamationmark")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.orange)
      Text(
        "Aufnahme war zu lang und wurde nach \(minutes) Min automatisch gestoppt. "
          + "Nur der Anfang wurde übernommen."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }
}

// MARK: - Shared footer (used on all pages)

private var appFooter: some View {
  HStack {
    Spacer()
    Button("Beenden") {
      NSApplication.shared.terminate(nil)
    }
    .font(.system(size: 10, weight: .medium))
    // Was .quaternary — too low contrast in dark mode; raised to .secondary
    .foregroundStyle(.secondary)
    .buttonStyle(SubtleButtonStyle())
    Spacer()
  }
  .padding(.vertical, 8)
}

// MARK: - Subtle Button Style

struct SubtleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.5 : 1.0)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

// MARK: - Shared recording body (deduplicates 4 identical copies)

/// Reusable recording affordance: waveform + stop button + hint.
/// Extracted from the 4 identical `recordingView` closures in the original file.
private struct RecordingBodyView: View {
  let audioLevel: Float
  let onStop: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Spacer().frame(height: 20)

      WaveformView(audioLevel: audioLevel, isRecording: true)
        .frame(height: 44)
        .padding(.horizontal, 24)

      Button(action: onStop) {
        ZStack {
          Circle()
            .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
            .frame(width: 44, height: 44)
          RoundedRectangle(cornerRadius: 3)
            .fill(.primary.opacity(0.7))
            .frame(width: 14, height: 14)
        }
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.return, modifiers: [])
      .accessibilityLabel("Aufnahme beenden")

      VStack(spacing: 4) {
        Text("Ich höre zu … Klicke zum Stoppen.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)

        Text("Enter = beenden · Esc = abbrechen")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }

      Spacer().frame(height: 8)
    }
  }
}

// MARK: - Transcription Active View

struct TranscriptionActiveView: View {
  @Bindable var workflow: TranscriptionWorkflow
  var copyOnly: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      switch workflow.phase {
      case .idle, .running:
        if workflow.isRecording {
          RecordingBodyView(audioLevel: workflow.audioLevel) { workflow.stop() }
        } else {
          processingView(message: "Wird transkribiert …")
        }

      case .done(let text):
        autoPasteView(text: text, copyOnly: copyOnly)

      case .error(let msg):
        errorView(message: msg) {
          workflow.reset()
          workflow.start()
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
  }
}

// MARK: - Text Improver Active View

struct TextImproverActiveView: View {
  @Bindable var workflow: TextImprovementWorkflow
  var copyOnly: Bool = false
  var fallbackNote: String?

  var body: some View {
    VStack(spacing: 0) {
      switch workflow.phase {
      case .idle, .running:
        if workflow.isRecording {
          RecordingBodyView(audioLevel: workflow.audioLevel) { workflow.stop() }
        } else {
          processingSpinner(phase: workflow.phase)
        }

      case .done(let text):
        autoPasteView(text: text, copyOnly: copyOnly, fallbackNote: fallbackNote)

      case .error(let msg):
        errorView(message: msg) {
          workflow.reset()
          workflow.start()
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
  }
}

// MARK: - Rage Mode Active View

struct DampfAblassenActiveView: View {
  @Bindable var workflow: DampfAblassenWorkflow
  var copyOnly: Bool = false
  var fallbackNote: String?

  var body: some View {
    VStack(spacing: 0) {
      switch workflow.phase {
      case .idle, .running:
        if workflow.isRecording {
          RecordingBodyView(audioLevel: workflow.audioLevel) { workflow.stop() }
        } else {
          processingSpinner(phase: workflow.phase)
        }

      case .done(let text):
        autoPasteView(text: text, copyOnly: copyOnly, fallbackNote: fallbackNote)

      case .error(let msg):
        errorView(message: msg) {
          workflow.reset()
          workflow.start()
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
  }
}

// MARK: - Emoji Text Active View

struct EmojiTextActiveView: View {
  @Bindable var workflow: EmojiTextWorkflow
  var copyOnly: Bool = false
  var fallbackNote: String?

  var body: some View {
    VStack(spacing: 0) {
      switch workflow.phase {
      case .idle, .running:
        if workflow.isRecording {
          RecordingBodyView(audioLevel: workflow.audioLevel) { workflow.stop() }
        } else {
          processingSpinner(phase: workflow.phase)
        }

      case .done(let text):
        autoPasteView(text: text, copyOnly: copyOnly, fallbackNote: fallbackNote)

      case .error(let msg):
        errorView(message: msg) {
          workflow.reset()
          workflow.start()
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
  }
}

// MARK: - Shared result / error views (free functions — no self capture needed)

private func processingView(message: String) -> some View {
  VStack(spacing: 12) {
    Spacer().frame(height: 24)
    ProgressView()
      .scaleEffect(0.7)
      .controlSize(.small)
    Text(message)
      .font(.system(size: 11.5))
      .foregroundStyle(.secondary)
    Spacer().frame(height: 24)
  }
}

/// Indeterminate spinner shown while a rewrite workflow is processing.
@ViewBuilder
private func processingSpinner(phase: WorkflowPhase) -> some View {
  VStack(spacing: 12) {
    Spacer().frame(height: 24)
    ProgressView()
      .scaleEffect(0.7)
      .controlSize(.small)
    if case .running(let msg) = phase {
      Text(msg)
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }
    Spacer().frame(height: 24)
  }
}

private func autoPasteView(text: String, copyOnly: Bool = false, fallbackNote: String? = nil)
  -> some View
{
  _AutoPasteView(text: text, copyOnly: copyOnly, fallbackNote: fallbackNote)
}

private struct _AutoPasteView: View {
  let text: String
  /// When the auto-paste couldn't run (no target / focus race lost), the text is only on the
  /// clipboard — show the manual-paste hint in orange instead of the green "Eingefügt".
  var copyOnly: Bool = false
  /// Quiet one-line note when this run fell back to a different rewrite model (B6). `nil` = hidden.
  var fallbackNote: String?
  @Environment(\.colorScheme) private var colorScheme

  private var accent: Color { copyOnly ? .orange : .green }
  private var iconName: String {
    copyOnly ? "doc.on.clipboard.fill" : "checkmark.circle.fill"
  }
  private var title: String { copyOnly ? "In die Zwischenablage kopiert" : "Eingefügt" }

  var body: some View {
    VStack(spacing: 12) {
      Spacer().frame(height: 20)

      ZStack {
        Circle()
          // Was hardcoded Color.green.opacity(0.1) — now colorScheme-aware
          .fill(MenuBarTokens.tintFill(accent, colorScheme: colorScheme))
          .frame(width: 44, height: 44)
        Image(systemName: iconName)
          .font(.system(size: 24))
          .foregroundStyle(accent)
      }

      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)

      if copyOnly {
        Text("Mit ⌘V einfügen.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      if let fallbackNote {
        Text(fallbackNote)
          .font(.system(size: 10.5))
          .foregroundStyle(.orange)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 8)
      }

      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(3)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)

      Spacer().frame(height: 12)
    }
  }
}

private func errorView(message: String, onRetry: @escaping () -> Void) -> some View {
  _ErrorView(message: message, onRetry: onRetry)
}

private struct _ErrorView: View {
  let message: String
  let onRetry: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 10) {
      Spacer().frame(height: 16)

      ZStack {
        Circle()
          // Was hardcoded Color.orange.opacity(0.1) — now colorScheme-aware
          .fill(MenuBarTokens.tintFill(.orange, colorScheme: colorScheme))
          .frame(width: 40, height: 40)
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 18))
          .foregroundStyle(.orange)
      }

      Text(message)
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)

      Button(action: onRetry) {
        Text("Nochmal versuchen")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(MenuBarTokens.cardStroke(colorScheme: colorScheme), lineWidth: 0.5)
          )
      }
      .buttonStyle(SubtleButtonStyle())
      .keyboardShortcut(.defaultAction)

      Spacer().frame(height: 4)
    }
  }
}
