import AppKit
import SwiftUI

// MARK: - System Settings (Tab 4: system)

struct SystemSettingsView: View {
  @Bindable var appState: AppState

  @Environment(\.colorScheme) private var colorScheme

  @State private var launchAtLoginService = LaunchAtLoginService()
  @State private var currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
  @State private var installActionErrorText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      // Section order per DESIGN.md:
      // (1) Bedienungshilfen — blocking prerequisite
      // (2) Installation & Start — blocking prerequisite
      // (3) Tastenkürzel
      // (4) Diktat — recording length + silence trimming
      // (5) Akustisches Feedback
      // (6) Einrichtung
      // (7) Updates
      // (8) Über & Lizenzen
      // (9) Sauber Entfernen — destructive, always trails
      AccessibilityPermissionSection(appState: appState)
        .settingsGroupBackground()

      installationAndStartSection
        .settingsGroupBackground()

      hotkeysSection
        .settingsGroupBackground()

      dictationSection
        .settingsGroupBackground()

      feedbackSection
        .settingsGroupBackground()

      setupSection
        .settingsGroupBackground()

      if UpdateService.isAvailable {
        updatesSection
          .settingsGroupBackground()
      }

      LicensesSection()
        .settingsGroupBackground()

      CleanupSection()
        .settingsGroupBackground()
    }
    .padding(16)
    .onAppear {
      launchAtLoginService.refresh()
      appState.updateService.refresh()
      refreshInstallState()
    }
  }

  // MARK: - Installation & Start (install location + login start, consolidated)

  private var installationAndStartSection: some View {
    // Plain section (SectionLabel + content), matching the other System sections.
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        SectionLabel(text: "installation & start", icon: "arrow.down.app")
        BlitzStatusPill(
          state: currentInstallLocation == .applications ? .ready : .warning,
          label: currentInstallLocation == .applications ? "sitzt" : "prüfen"
        )
        Spacer()
      }

      Text(installationHeadline)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.primary)

      Text(installationDetail)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Text(BlitztextInstallLocationService.bundleURL.path)
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
        Text("weitere rede-kopien auf diesem Mac können doppelte login-items auslösen.")
          .font(.system(size: 10.5))
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }

      installActionButtons

      if let installActionErrorText {
        Text(installActionErrorText)
          .font(.system(size: 10.5))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      // Status → action → optional details: the long rationale lives behind the disclosure
      // (DESIGN.md: kein dauerhafter Erklärungstext).
      InfoDisclosure("warum /Applications?") {
        Text(
          "für direktes einfügen und stabile hotkeys: rede einmal nach /Applications legen, "
            + "danach mikrofon und bedienungshilfen erlauben. so bleiben anmeldestart, updates "
            + "und TCC-freigaben an einer einzigen app-kopie hängen."
        )
      }

      launchAtLoginRow
    }
  }

  private var installActionButtons: some View {
    HStack(spacing: 8) {
      if BlitztextInstallLocationService.shouldOfferMoveToApplications {
        Button {
          moveToApplications()
        } label: {
          Label("nach /Applications bewegen", systemImage: "arrow.down.app.fill")
        }
        .buttonStyle(PopoverActionButtonStyle(.warning))
      }

      Button {
        revealInFinder(urls: [BlitztextInstallLocationService.bundleURL])
      } label: {
        Label("im Finder zeigen", systemImage: "finder")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))

      if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
        Button {
          revealInFinder(urls: BlitztextInstallLocationService.otherInstalledBundleURLs)
        } label: {
          Label("weitere kopien zeigen", systemImage: "square.stack.3d.up")
        }
        .buttonStyle(PopoverActionButtonStyle(.warning))
      }
    }
  }

  private var launchAtLoginRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle(
        "rede automatisch starten",
        isOn: Binding(
          get: { launchAtLoginService.isEnabled },
          set: { launchAtLoginService.setEnabled($0) }
        )
      )
      .toggleStyle(.switch)
      .controlSize(.small)

      Text(launchAtLoginService.errorText ?? launchAtLoginService.helperText)
        .font(.system(size: 10.5))
        .foregroundStyle(
          launchAtLoginService.errorText == nil
            ? AnyShapeStyle(.secondary)
            : AnyShapeStyle(.red)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Einrichtung

  private var setupSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "einrichtung", icon: "sparkles")

      Text("die geführte ersteinrichtung jederzeit erneut durchlaufen.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Button {
        NotificationCenter.default.post(name: .openOnboardingWindow, object: nil)
      } label: {
        Label("einrichtung erneut starten", systemImage: "arrow.counterclockwise")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
    }
  }

  // MARK: - Updates

  private var updatesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "updates", icon: "arrow.triangle.2.circlepath")

      HStack(spacing: 8) {
        Text(appState.updateService.appVersionText)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)

        if let hint = UpdateService.updateHintText(
          forVersion: appState.updateService.availableUpdateVersion)
        {
          BlitzStatusPill(state: .download, label: hint)
        }
      }

      Text(appState.updateService.lastCheckDisplayText)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)

      Button {
        appState.updateService.checkForUpdates()
      } label: {
        Label("jetzt nach updates suchen", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
      .disabled(!appState.updateService.canCheckForUpdates)

      Toggle(
        "automatisch täglich prüfen",
        isOn: Binding(
          get: { appState.updateService.automaticChecksEnabled },
          set: { appState.updateService.setAutomaticChecksEnabled($0) }
        )
      )
      .toggleStyle(.switch)
      .controlSize(.small)

      // Compact data-flow note (DESIGN.md: sensible Hinweise als sichtbare Caption).
      Text("übertragen wird nur die app-version — keine weiteren daten, kein geräteprofil.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Tastenkürzel
  // One section heading, then the hold/toggle decision with its explainer, then the read-only
  // per-mode table. Editing a combination lives in the mode card (Prompts tab) — the caption
  // says so instead of duplicating a recorder here.

  private var hotkeysSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(text: "tastenkürzel", icon: "keyboard")

      VStack(alignment: .leading, spacing: 6) {
        Picker("", selection: $appState.appSettings.hotkeyMode) {
          ForEach(HotkeyMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()

        Text(appState.appSettings.hotkeyMode.description)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        // Warnings immediately below the picker
        hotkeyWarnings
      }

      // Read-only per-mode table below the picker
      VStack(spacing: 6) {
        ForEach(appState.mainMenuModeConfigs) { config in
          HStack {
            Text(appState.hotkeyLabel(for: config.id))
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.secondary)
              .frame(width: 124, alignment: .leading)
            Text(appState.displayName(for: config))
              .font(.system(size: 11.5, weight: .medium))
            Spacer()
          }
        }
      }

      Text("ändern kannst du jede kombination pro modus im tab prompts.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var hotkeyWarnings: some View {
    if !appState.hotkeyValidationIssues.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(hotkeyWarningRows, id: \.self) { row in
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.orange)
            Text(row)
              .font(.system(size: 10.5))
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .liquidGlassInfoBanner(accent: .orange)
    }
  }

  private var hotkeyWarningRows: [String] {
    appState.hotkeyValidationIssues.map { issue in
      switch issue {
      case .duplicate(let label, let modeIDs):
        let names = modeIDs.map(modeDisplayName).joined(separator: ", ")
        return "\(label): \(names)"
      }
    }
  }

  private func modeDisplayName(_ modeID: ModeConfig.ID) -> String {
    guard let config = appState.modeConfig(for: modeID) else { return modeID }
    return appState.displayName(for: config)
  }

  // MARK: - Diktat (Länge + Pausen)

  /// Selectable dictation length caps (minutes). The cap is only a runaway guard — these are all
  /// comfortably under whisper-1's 25 MB online limit at 16 kHz mono.
  private static let dictationLengthOptions = [3, 10, 30, 60]

  private var dictationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "diktat", icon: "mic")

      Text("maximale aufnahmelänge")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      Picker("", selection: $appState.appSettings.maxDictationMinutes) {
        ForEach(Self.dictationLengthOptions, id: \.self) { minutes in
          Text("\(minutes) Min").tag(minutes)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Toggle(
        "sprechpausen automatisch kürzen",
        isOn: $appState.appSettings.silenceTrimmingEnabled
      )
      .toggleStyle(.switch)
      .controlSize(.small)
      .padding(.top, 4)

      // Privacy-relevant one-liner stays visible; the long rationale moves behind the disclosure.
      Text("pausen-kürzung läuft komplett auf deinem Mac — es wird nichts zusätzlich verschickt.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      InfoDisclosure("wie funktioniert das?") {
        VStack(alignment: .leading, spacing: 5) {
          Text(
            "die aufnahmelänge schützt nur vor vergessenen aufnahmen — du kannst problemlos "
              + "mehrere minuten am stück diktieren. bei der online-transkription bleibt das "
              + "25-MB-Limit von OpenAI bestehen."
          )
          Text(
            "pausen-kürzung schneidet längere gesprächspausen vor der transkription heraus — "
              + "kürzeres audio, schnellere und günstigere online-verarbeitung."
          )
        }
      }
    }
  }

  // MARK: - Akustisches Feedback

  private var feedbackSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "akustisches feedback", icon: "speaker.wave.2")

      Toggle(
        "töne bei start, fertig und fehler",
        isOn: $appState.appSettings.soundFeedbackEnabled
      )
      .toggleStyle(.switch)
      .controlSize(.small)

      Text(
        "kurze systemtöne als rückmeldung — praktisch für diktate per hintergrund-hotkey, ohne "
          + "hinzusehen."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if appState.appSettings.soundFeedbackEnabled {
        HStack(spacing: 12) {
          Text("anhören:")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
          Button("start") { EarconPlayer.play(.start) }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .font(.system(size: 10.5, weight: .medium))
          Button("fertig") { EarconPlayer.play(.done) }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .font(.system(size: 10.5, weight: .medium))
          Button("fehler") { EarconPlayer.play(.error) }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .font(.system(size: 10.5, weight: .medium))
        }
      }
    }
  }

  // MARK: - Helpers

  private var installationHeadline: String {
    switch currentInstallLocation {
    case .applications:
      return "rede liegt am richtigen ort."
    case .userApplications:
      return "rede liegt noch in ~/Applications."
    case .outsideApplications:
      return "rede liegt noch nicht in /Applications."
    case .unknown:
      return "der installationsort konnte nicht sicher erkannt werden."
    }
  }

  private var installationDetail: String {
    switch currentInstallLocation {
    case .applications:
      if BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
        return "für stabile login-items und updates nur diese kopie weiterverwenden."
      }
      return "diese kopie ist korrekt. zusätzliche kopien solltest du später entfernen."
    case .userApplications:
      return "für stabile hotkeys und login-items sollte rede nur aus /Applications laufen."
    case .outsideApplications:
      return
        "verschiebe rede einmal nach /Applications, damit anmeldestart und hotkeys sauber bleiben."
    case .unknown:
      return "öffne rede möglichst direkt aus /Applications."
    }
  }

  private func refreshInstallState() {
    currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
    installActionErrorText = nil
  }

  private func moveToApplications() {
    installActionErrorText = nil

    do {
      try BlitztextInstallLocationService.moveToApplicationsAndRelaunch()
    } catch {
      installActionErrorText = error.localizedDescription
    }
  }

  private func revealInFinder(urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }
}
