import AppKit
import SwiftUI

// MARK: - System Settings (Tab 3: System)

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
    // Was the only SettingsSection/GroupBox card here — the lone grey box read as inconsistent.
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Installation & Start")

      Text(
        "Für direktes Einfügen und stabile Hotkeys: rede einmal nach /Applications legen, "
          + "danach Mikrofon und Bedienungshilfen erlauben."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

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
        Text("Weitere rede-Kopien auf diesem Mac können doppelte Login-Items auslösen.")
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

      launchAtLoginRow
    }
  }

  private var installActionButtons: some View {
    HStack(spacing: 8) {
      if BlitztextInstallLocationService.shouldOfferMoveToApplications {
        Button("Nach /Applications bewegen") {
          moveToApplications()
        }
        .buttonStyle(PopoverActionButtonStyle(.warning))
      }

      Button("Im Finder zeigen") {
        revealInFinder(urls: [BlitztextInstallLocationService.bundleURL])
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))

      if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
        Button("Weitere Kopien zeigen") {
          revealInFinder(urls: BlitztextInstallLocationService.otherInstalledBundleURLs)
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
      SectionLabel(text: "Einrichtung")

      Text("Die geführte Ersteinrichtung jederzeit erneut durchlaufen.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Button("Einrichtung erneut starten") {
        NotificationCenter.default.post(name: .openOnboardingWindow, object: nil)
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
    }
  }

  // MARK: - Updates

  private var updatesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Updates")

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

      Button("Jetzt nach Updates suchen") {
        appState.updateService.checkForUpdates()
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
      .disabled(!appState.updateService.canCheckForUpdates)

      Toggle(
        "Automatisch täglich prüfen",
        isOn: Binding(
          get: { appState.updateService.automaticChecksEnabled },
          set: { appState.updateService.setAutomaticChecksEnabled($0) }
        )
      )
      .toggleStyle(.switch)
      .controlSize(.small)

      Text(
        "Die Prüfung fragt nur die Update-Liste des Projekts ab — übertragen wird dabei lediglich "
          + "die App-Version im Anfrage-Header. Keine weiteren Daten, kein Geräteprofil."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Tastenkürzel
  // Modus picker promoted above hotkey table. SectionLabel used as picker label.
  // hotkeyWarnings appear immediately below the picker.

  private var hotkeysSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(text: "Tastenkürzel")

      // Modus picker first (promoted above the table per spec)
      VStack(alignment: .leading, spacing: 6) {
        SectionLabel(text: "Modus")

        Picker("", selection: $appState.appSettings.hotkeyMode) {
          ForEach(HotkeyMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()

        // Warnings immediately below the picker
        hotkeyWarnings
      }

      // Hotkey table below the picker
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
      SectionLabel(text: "Diktat")

      Text("Maximale Aufnahmelänge")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      Picker("", selection: $appState.appSettings.maxDictationMinutes) {
        ForEach(Self.dictationLengthOptions, id: \.self) { minutes in
          Text("\(minutes) Min").tag(minutes)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Text(
        "Schützt nur vor vergessenen Aufnahmen — du kannst problemlos mehrere Minuten am Stück "
          + "diktieren. Bei der Online-Transkription bleibt das 25-MB-Limit von OpenAI bestehen."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Toggle(
        "Sprechpausen automatisch kürzen",
        isOn: $appState.appSettings.silenceTrimmingEnabled
      )
      .toggleStyle(.switch)
      .controlSize(.small)
      .padding(.top, 4)

      Text(
        "Schneidet längere Gesprächspausen vor der Transkription heraus — kürzeres Audio, schnellere "
          + "und günstigere Online-Verarbeitung. Läuft komplett auf deinem Mac; es wird nichts "
          + "zusätzlich verschickt."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Akustisches Feedback

  private var feedbackSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Akustisches Feedback")

      Toggle(
        "Töne bei Start, Fertig und Fehler",
        isOn: $appState.appSettings.soundFeedbackEnabled
      )
      .toggleStyle(.switch)
      .controlSize(.small)

      Text(
        "Kurze Systemtöne als Rückmeldung — praktisch für Diktate per Hintergrund-Hotkey, ohne "
          + "hinzusehen."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if appState.appSettings.soundFeedbackEnabled {
        HStack(spacing: 12) {
          Text("Anhören:")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
          Button("Start") { EarconPlayer.play(.start) }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .font(.system(size: 10.5, weight: .medium))
          Button("Fertig") { EarconPlayer.play(.done) }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .font(.system(size: 10.5, weight: .medium))
          Button("Fehler") { EarconPlayer.play(.error) }
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
      return "rede liegt am richtigen Ort."
    case .userApplications:
      return "rede liegt noch in ~/Applications."
    case .outsideApplications:
      return "rede liegt noch nicht in /Applications."
    case .unknown:
      return "Der Installationsort konnte nicht sicher erkannt werden."
    }
  }

  private var installationDetail: String {
    switch currentInstallLocation {
    case .applications:
      if BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
        return "Für stabile Login-Items und Updates nur diese Kopie weiterverwenden."
      }
      return "Diese Kopie ist korrekt. Zusätzliche Kopien solltest du später entfernen."
    case .userApplications:
      return "Für stabile Hotkeys und Login-Items sollte rede nur aus /Applications laufen."
    case .outsideApplications:
      return
        "Verschiebe rede einmal nach /Applications, damit Anmeldestart und Hotkeys sauber bleiben."
    case .unknown:
      return "Öffne rede möglichst direkt aus /Applications."
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
