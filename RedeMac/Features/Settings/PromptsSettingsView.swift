import SwiftUI

/// Tab "Modi": every visible mode. Each card owns its name, hotkey, behavior and reset.
struct PromptsSettingsView: View {
  @Bindable var appState: AppState
  /// Jump to another settings tab (e.g. "Zu Modelle" when no rewrite engine is connected yet).
  let selectTab: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 8) {
        SectionLabel(text: "modi", icon: "rectangle.stack")
        RedeStatusPill(
          state: appState.hasActiveRewriteEngine ? .ready : .warning,
          label: appState.hasActiveRewriteEngine ? "bereit" : "modell fehlt"
        )
        Spacer()
        addModeMenu
      }

      if !appState.hasActiveRewriteEngine {
        EmptyStateCard(
          icon: "wand.and.stars",
          title: "noch kein umschreib-modell verbunden",
          caption: missingRewriteEngineCaption,
          accent: .purple,
          buttonLabel: "zu modelle",
          action: { selectTab(1) }
        )
      }

      ForEach(visibleModes) { config in
        ModeCardView(appState: appState, config: config)
      }

      InfoDisclosure("was modi tun") {
        Text(
          "Freitext fügt nur das diktat ein. E-Mail, Prompt und Social formulieren dein diktat mit eigenen anweisungen um."
        )
      }
    }
    .padding(16)
  }

  private var visibleModes: [ModeConfig] {
    appState.orderedModeConfigs.filter { $0.slot != .localTranscription }
  }

  private var addModeMenu: some View {
    Menu {
      ForEach(ModeTemplate.allCases) { template in
        Button {
          appState.addMode(template: template)
        } label: {
          Label(template.displayName, systemImage: template.icon)
        }
        .disabled(template.slot.isRewriteCapable && !appState.hasActiveRewriteEngine)
      }
    } label: {
      Image(systemName: "plus")
    }
    .buttonStyle(PopoverIconButtonStyle(.secondary))
    .help("modus hinzufügen")
    .accessibilityLabel("Modus hinzufügen")
  }

  private var missingRewriteEngineCaption: String {
    appState.appSettings.secureLocalModeEnabled
      ? "lokale modi brauchen ein geladenes llama.cpp/GGUF-Modell. online-key und lokales modell werden nicht gemischt."
      : "online-modi brauchen einen OpenAI API-Key. lokale modelle werden im online-modus nicht verwendet."
  }
}
