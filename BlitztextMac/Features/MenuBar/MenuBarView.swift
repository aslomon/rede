import AppKit
import SwiftUI

// MARK: - Brand mark

/// Small rede brand mark (the menu-bar bars), tinted to the foreground colour. Loaded from the
/// bundled `menubar_icon` resource via NSImage (it is not in an asset catalog, so `Image("…")` can't
/// find it). Used in the popover AND window headers for a consistent brand anchor.
struct BrandMark: View {
  var size: CGFloat = 15

  var body: some View {
    Image(nsImage: NSImage(named: "menubar_icon") ?? NSImage())
      .resizable()
      .renderingMode(.template)
      .aspectRatio(contentMode: .fit)
      .frame(width: size, height: size)
      .foregroundStyle(.primary)
      .accessibilityHidden(true)
  }
}

/// The rede wordmark: lowercase "rede" in SF Rounded bold + an oversized brand accent dot —
/// "rede." IS the name. The dot is a drawn circle (bigger and bolder than a typographic period),
/// lime on dark surfaces and violet on light (lime washes out on white) — see RedeBrand.dotColor.
struct Wordmark: View {
  var size: CGFloat = 16
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: size * 0.07) {
      Text("rede")
        .font(.system(size: size, weight: .bold, design: .rounded))
        .foregroundStyle(.primary)
      Circle()
        .fill(RedeBrand.dotColor(colorScheme))
        .frame(width: size * 0.30, height: size * 0.30)
        // Sit the dot on the text baseline (a period rests there too).
        .alignmentGuide(.firstTextBaseline) { dimension in dimension[.bottom] }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("rede")
  }
}

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
    // The SwiftUI root width IS the popover width (it overrides NSPopover.contentSize). Width stays
    // at the compact 410; the dense settings page just gets more HEIGHT so more fits before scrolling.
    .frame(width: 410)
    .frame(minHeight: appState.page == .settings ? 600 : 0, alignment: .top)
    // Opaque backstop: fixes dark-mode transparency wash-out (macOS 26 glass / <26 material).
    .blitztextSurface()
    // rede voice: SF Rounded across the popover for a young, friendly tone. Monospaced runs
    // (hotkeys, paths) opt out explicitly with .monospaced, so they are unaffected.
    .fontDesign(.rounded)
    .animation(.easeInOut(duration: 0.2), value: appState.page)
  }
}

// MARK: - Main Page

private struct MainPageView: View {
  @Bindable var appState: AppState
  @Environment(\.colorScheme) private var colorScheme

  // MARK: State for engine footer expand/collapse (spec change #1)
  @State private var engineExpanded = false
  // MARK: Namespace for workflow row glass morphing (spec change #6)
  @Namespace private var rowNamespace

  var body: some View {
    VStack(spacing: 0) {
      headerBand

      if BlitztextInstallLocationService.shouldOfferMoveToApplications {
        installHintBanner
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 6)
      }

      if !appState.accessibilityPermissionGranted {
        accessibilityHintBanner
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 6)
      }

      workflowList
        .padding(.vertical, 2)

      // Engine/model selection lives only in Settings → Modelle now; the popover start page no
      // longer carries the bottom engine bar.
      AppFooter(appState: appState)
    }
  }

  // MARK: Header

  private var headerBand: some View {
    VStack(spacing: 0) {
      HStack(spacing: 7) {
        BrandMark()
        Wordmark(size: 16)
        if appState.isConfigured {
          BlitzStatusPill(state: .ready, label: "läuft")
        }

        Spacer()

        Button {
          appState.openSettings()
        } label: {
          ZStack(alignment: .topTrailing) {
            Image(systemName: "gear")

            if !appState.accessibilityPermissionGranted {
              Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .offset(x: -4, y: 4)
            } else if appState.updateService.availableUpdateVersion != nil {
              // Quiet update cue on the gear (blue = download, per design tokens).
              Circle()
                .fill(Color.blue)
                .frame(width: 6, height: 6)
                .offset(x: -4, y: 4)
            }
          }
        }
        .buttonStyle(PopoverIconButtonStyle(.quiet))
        .help("Einstellungen")
        .accessibilityLabel("Einstellungen")
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, appState.isConfigured ? 12 : 8)

      // Setup CTA only in the unconfigured state; the configured "Bereit" pill now sits inline above.
      if !appState.isConfigured {
        unconfiguredStatusLine
          .padding(.bottom, 12)
      }
    }
    .background(MenuBarTokens.headerBand(colorScheme: colorScheme))
  }

  // MARK: Status lines

  // Spec change #4: Replace raw Circle dot + Text with BlitzStatusPill(.ready)
  private var configuredStatusLine: some View {
    BlitzStatusPill(state: .ready, label: "Bereit")
  }

  // Spec change #5: Remove the three-line body Text paragraph; keep icon circle, headline, button
  private var unconfiguredStatusLine: some View {
    VStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(MenuBarTokens.tintFill(.orange, colorScheme: colorScheme))
          .frame(width: 40, height: 40)
        Image(systemName: "key.fill")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.orange)
      }

      Text("Einrichtung nötig")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)

      Button {
        NotificationCenter.default.post(name: .openOnboardingWindow, object: nil)
      } label: {
        Label("Einrichten", systemImage: "sparkles")
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
    }
  }

  // MARK: Engine Footer (spec change #1 + #2)
  //
  // Compressed to a BlitzStatusPill at rest; tap to reveal the full enginePanel inline.
  // Saves ~60pt vertical space in the default state.

  private var engineFooter: some View {
    VStack(spacing: 0) {
      // Compressed pill — always visible
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          engineExpanded.toggle()
        }
      } label: {
        HStack(spacing: 6) {
          BlitzStatusPill(
            state: appState.appSettings.secureLocalModeEnabled ? .local : .online,
            label: engineStatusSummary
          )
          Spacer()
          Image(systemName: engineExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Transkriptions-Engine")
      .accessibilityHint(engineExpanded ? "Einklappen" : "Ausklappen")

      // Expanded engine panel (spec change #2: .liquidGlassCard replaces manual RoundedRect)
      if engineExpanded {
        enginePanel
          .padding(.top, 4)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  /// One-line summary shown in the compressed pill label.
  private var engineStatusSummary: String {
    if appState.appSettings.secureLocalModeEnabled {
      if appState.isDownloadingLocalModel {
        return appState.localModelDownloadStatusText ?? "Modell wird geladen…"
      }
      if appState.selectedLocalModelIsInstalled {
        return "Lokal · \(appState.selectedLocalModelDisplayName)"
      }
      return "\(appState.selectedLocalModelDisplayName) nicht geladen"
    }
    return "Online · Whisper"
  }

  // MARK: Engine Panel

  // Spec change #2: .liquidGlassCard() replaces the manual RoundedRectangle fill + overlay pair
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
          .buttonStyle(PopoverActionButtonStyle(.primary))
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
    .liquidGlassCard(cornerRadius: LiquidGlass.cardCornerRadius)
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

  // Spec change #3: .liquidGlassInfoBanner(accent: .orange) replaces manual tintFill + strokeBorder
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
      .buttonStyle(PopoverActionButtonStyle(.warning))
    }
    .padding(10)
    .liquidGlassInfoBanner(accent: .orange)
  }

  // Spec change #3: same treatment for installHintBanner
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
        appState.openSettings(tab: 4)
      }
      .font(.system(size: 10.5, weight: .medium))
      .buttonStyle(PopoverActionButtonStyle(.warning))
    }
    .padding(10)
    .liquidGlassInfoBanner(accent: .orange)
  }

  // MARK: Workflow list (spec change #6)
  //
  // ForEach wrapped in GlassEffectContainerView for adjacent-row morphing on macOS 26.
  // rowNamespace is passed down so .glassEffectID works across all rows.

  private var workflowList: some View {
    GlassEffectContainerView(spacing: 0, axis: .vertical) {
      ForEach(appState.mainMenuModeConfigs) { config in
        let enabled = appState.isWorkflowAvailable(config)
        WorkflowRowView(
          type: config.slot,
          enabled: enabled,
          customName: appState.displayName(for: config),
          subtitle: appState.workflowSubtitle(for: config),
          hotkeyLabel: appState.hotkeyLabel(for: config.id),
          namespace: rowNamespace
        ) {
          appState.startModeFromPopover(config.id)
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
        .buttonStyle(PopoverActionButtonStyle(.quiet))

        Spacer()

        HStack(spacing: 6) {
          BrandMark(size: 13)
          Text("Einstellungen")
            .font(.system(size: 12, weight: .semibold))
        }

        Spacer()
        settingsQuickAction
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(MenuBarTokens.headerBand(colorScheme: colorScheme))

      SettingsContentView(appState: appState)

      Spacer(minLength: 0)

      AppFooter(appState: appState)
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
      .buttonStyle(PopoverActionButtonStyle(.warning))
    } else {
      Color.clear.frame(width: 58, height: 18)
    }
  }
}

// MARK: - Workflow Page

private struct WorkflowPageView: View {
  @Bindable var appState: AppState
  // Spec change #10: colorScheme needed for headerBand
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      if let workflow = appState.activeWorkflow {
        workflowHeader(workflow: workflow)

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

        AppFooter(appState: appState)
      }
    }
  }

  // Spec change #10: .semibold size 13, headerBand background, Divider, accent on icon
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
      .buttonStyle(PopoverActionButtonStyle(.quiet))

      Spacer()

      HStack(spacing: 5) {
        Image(systemName: workflow.type.icon)
          .font(.system(size: 11))
          // Accent colour explicitly set — not overridden by .primary
          .foregroundStyle(workflow.type.accentColorValue)
        Text(appState.displayName(for: workflow.type))
          // Spec change #10: .semibold weight, size 13
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(MenuBarTokens.headerBand(colorScheme: colorScheme))
  }

  // Spec change #11: .liquidGlassInfoBanner(accent: .orange) replaces manual padding+background+overlay
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
    .padding(10)
    .liquidGlassInfoBanner(accent: .orange)
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }
}

// MARK: - Shared footer (used on all pages)

/// Trailing-aligned footer: quiet version label left, optional update hint + Beenden right.
/// The update button is the popover's secondary entry into the updater (primary lives in
/// Einstellungen → System → Updates); it appears only while a gentle update reminder waits.
private struct AppFooter: View {
  @Bindable var appState: AppState

  var body: some View {
    HStack(spacing: 8) {
      Text(appState.updateService.appVersionText)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)

      Spacer()

      if let hint = UpdateService.updateHintText(
        forVersion: appState.updateService.availableUpdateVersion)
      {
        Button(hint) {
          appState.updateService.checkForUpdates()
        }
        .font(.system(size: 10, weight: .medium))
        .buttonStyle(PopoverActionButtonStyle(.primary))
      }

      Button("Beenden") {
        NSApplication.shared.terminate(nil)
      }
      .font(.system(size: 10, weight: .medium))
      .buttonStyle(PopoverActionButtonStyle(.quiet))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
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

      // Spec change #13: GlassActionButtonStyle on macOS 26; existing Circle+RoundedRect
      // construction lives inside GlassActionButtonStyle's macOS 14–25 fallback path.
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
      .buttonStyle(GlassActionButtonStyle())
      .keyboardShortcut(.return, modifiers: [])
      // Spec change #13: accessibilityLabel verified present
      .accessibilityLabel("Aufnahme beenden")

      VStack(spacing: 4) {
        Text("läuft … ich hör zu. klick zum stoppen.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)

        Text("enter = beenden · esc = abbrechen")
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
          processingView(message: "wird transkribiert …")
        }

      case .done(let text):
        autoPasteView(text: text, copyOnly: copyOnly)

      case .variantChoice:
        variantChoicePopoverHint()

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

      case .variantChoice:
        variantChoicePopoverHint()

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

      case .variantChoice:
        variantChoicePopoverHint()

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

      case .variantChoice:
        variantChoicePopoverHint()

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

private func variantChoicePopoverHint() -> some View {
  VStack(spacing: 12) {
    Spacer().frame(height: 20)
    Image(systemName: "square.split.2x1")
      .font(.system(size: 24, weight: .semibold))
      .foregroundStyle(.secondary)
    Text("version in der pille wählen")
      .font(.system(size: 13, weight: .semibold))
    Text("kommt erst nach deiner auswahl rein.")
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
    Spacer().frame(height: 12)
  }
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
  private var title: String { copyOnly ? "kopiert — liegt bereit" : "sitzt." }

  var body: some View {
    // Spec change #14: .padding(.top, 16) on VStack replaces Spacer().frame(height: 20)
    VStack(spacing: 12) {
      ZStack {
        Circle()
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
        Text("einfach mit ⌘V einfügen.")
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

      // Spec change #14: .lineLimit(1), .leading alignment
      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)

      Spacer().frame(height: 12)
    }
    .padding(.top, 16)
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
        Text("nochmal")
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
      .buttonStyle(PopoverActionButtonStyle(.primary))
      .keyboardShortcut(.defaultAction)

      Spacer().frame(height: 4)
    }
  }
}
