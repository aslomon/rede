import SwiftUI

/// Step: how recordings start. One decision — hold vs. toggle — plus a read-only keycap overview
/// of the default per-mode hotkeys so the core interaction is learned before the wizard ends.
/// Editing individual combinations stays in Einstellungen → Prompts (per mode card).
struct HotkeysStepView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      modeCard

      hotkeyListCard
    }
  }

  // MARK: - Hold vs. toggle (the decision)

  private var modeCard: some View {
    OnboardingCard(accent: .indigo) {
      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "auslösen", icon: "keyboard")

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
      }
    }
  }

  // MARK: - Read-only hotkey overview

  private var hotkeyListCard: some View {
    OnboardingCard {
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel(text: "deine modi", icon: "rectangle.stack")

        VStack(spacing: 8) {
          ForEach(appState.mainMenuModeConfigs) { config in
            let hotkey = appState.hotkeyConfig(for: config.id)
            ModeHotkeyRow(
              icon: config.slot.icon,
              accent: config.slot.accentColorValue,
              name: appState.displayName(for: config),
              hotkeyLabel: hotkey.isConfigured ? hotkey.label : nil
            )
          }
        }

        Text("ändern kannst du jede kombination später pro modus in den einstellungen.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
