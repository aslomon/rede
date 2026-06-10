import SwiftUI

/// Final step: a recap of what got configured. The primary "fertig" and secondary "zu den
/// einstellungen" buttons live in the shared footer (change 4). This step owns only the recap.
struct FinishStepView: View {
  @Bindable var appState: AppState
  /// Invoked by the footer's "zu den einstellungen": finishes onboarding, closes the wizard, opens
  /// the popover settings. Wired by the wizard root so this step stays free of window plumbing.
  let onOpenSettings: () -> Void

  @State private var launchAtLoginService = LaunchAtLoginService()

  private var micGranted: Bool { MicrophonePermissionService.currentStatus.isGranted }

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      successHeader

      OnboardingCard {
        VStack(alignment: .leading, spacing: 10) {
          OnboardingRecapRow(
            title: "mikrofon",
            detail: micGranted ? "erlaubt" : "noch nicht erteilt — kannst du später nachholen.",
            isPositive: micGranted)
          OnboardingRecapRow(
            title: "bedienungshilfen",
            detail: appState.accessibilityPermissionGranted
              ? "erkannt — direktes einfügen ist frei." : "noch nicht erkannt.",
            isPositive: appState.accessibilityPermissionGranted)
          OnboardingRecapRow(
            title: "verarbeitung",
            detail: processingDetail,
            isPositive: processingReady)
          OnboardingRecapRow(
            title: "Whisper",
            detail: whisperDetail,
            isPositive: whisperReady)
          OnboardingRecapRow(
            title: "modi & hotkeys",
            detail: modesDetail,
            isPositive: true)
          OnboardingRecapRow(
            title: "extras",
            detail: extrasDetail,
            isPositive: launchAtLoginService.isEnabled
              || appState.appSettings.soundFeedbackEnabled
              || appState.isUnifiedMemoryEnabled)
        }
      }

      // discoverCard collapsed behind InfoDisclosure (change 12)
      InfoDisclosure("was du später entdecken kannst") {
        discoverContent
      }
    }
    .onAppear { launchAtLoginService.refresh() }
  }

  // MARK: - Success header

  /// 44pt checkmark circle: glass capsule on macOS 26+, flat green circle on macOS 14–25 (change 12).
  private var successHeader: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.green.opacity(0.12))
          .frame(width: 44, height: 44)
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 24))
          .foregroundStyle(.green)
      }
      // liquidGlassCapsule provides the macOS 26 glass celebration moment;
      // on macOS 14–25 it falls back to .regularMaterial + shadow (change 12).
      .liquidGlassCapsule(accent: .green)
      .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 3) {
        Text("sitzt.")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
        Text("hier ist deine einrichtung im überblick. mit \u{201E}fertig\u{201C} legst du los.")
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  // MARK: - Discover content (behind InfoDisclosure, change 12)

  /// Surfaces the optional, on-device extras a first-run user wouldn't otherwise discover.
  private var discoverContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      discoverRow(
        "archivebox",
        "lokales archiv & diktier-statistik — opt-in, alles bleibt auf deinem Mac.")
      discoverRow(
        "wand.and.stars",
        "lernt aus deinen korrekturen und schlägt feste wörterbuch-wörter vor.")
      discoverRow(
        "character.cursor.ibeam",
        "eigene begriffe und ersetzungen für namen, marken und fachwörter — im tab vokabular.")
    }
  }

  private func discoverRow(_ icon: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.blue)
        .frame(width: 16)
      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Recap derivations

  private var isLocal: Bool { appState.appSettings.secureLocalModeEnabled }

  private var processingReady: Bool {
    isLocal ? appState.selectedLocalModelIsInstalled : KeychainService.isConfigured
  }

  private var processingDetail: String {
    if isLocal {
      return "sicherer lokaler modus — alles bleibt auf diesem Mac."
    }
    return KeychainService.isConfigured
      ? "online über OpenAI — API-Key hinterlegt." : "online gewählt, aber kein API-Key."
  }

  private var whisperReady: Bool {
    isLocal ? appState.selectedLocalModelIsInstalled : true
  }

  private var whisperDetail: String {
    if !isLocal { return "online über OpenAI Whisper." }
    return appState.selectedLocalModelIsInstalled
      ? "\u{201E}\(appState.selectedLocalModelDisplayName)\u{201C} ist geladen."
      : "lokales modell fehlt noch."
  }

  private var modesDetail: String {
    let trigger = appState.appSettings.hotkeyMode == .hold ? "halten" : "umschalten"
    return "E-Mail, Prompt und Social vorbereitet — hotkeys im \(trigger)-modus."
  }

  private var extrasDetail: String {
    var active: [String] = []
    if launchAtLoginService.isEnabled { active.append("autostart") }
    if appState.appSettings.soundFeedbackEnabled { active.append("töne") }
    if appState.isUnifiedMemoryEnabled { active.append("archiv & memory") }
    guard !active.isEmpty else { return "keine extras aktiviert — geht jederzeit im system-tab." }
    return active.joined(separator: " · ")
  }
}
