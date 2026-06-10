import SwiftUI

/// Step: how recordings start. One decision — hold vs. toggle — plus a read-only keycap overview
/// of the default per-mode hotkeys so the core interaction is learned before the wizard ends.
/// Editing individual combinations stays in Einstellungen → Prompts (per mode card).
struct HotkeysStepView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingStepHeader(
        systemImage: "keyboard",
        accent: .indigo,
        title: "deine hotkeys",
        subtitle: "so startest du jeden modus von überall — ohne die menüleiste zu öffnen."
      )

      modeCard

      hotkeyListCard
    }
  }

  // MARK: - Hold vs. toggle (the decision)

  private var modeCard: some View {
    OnboardingCard(accent: .indigo) {
      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "auslösen")

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
        SectionLabel(text: "deine modi")

        VStack(spacing: 8) {
          ForEach(appState.mainMenuModeConfigs) { config in
            hotkeyRow(config)
          }
        }

        Text("ändern kannst du jede kombination später pro modus in den einstellungen.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func hotkeyRow(_ config: ModeConfig) -> some View {
    let hotkey = appState.hotkeyConfig(for: config.id)
    return HStack(spacing: 8) {
      Image(systemName: config.slot.icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(config.slot.accentColorValue)
        .frame(width: 16)
      Text(appState.displayName(for: config))
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
      Spacer(minLength: 8)
      if hotkey.isConfigured {
        HotkeyBadge(label: hotkey.label, enabled: true)
      } else {
        Text("nicht gesetzt")
          .font(.system(size: 10.5))
          .foregroundStyle(.tertiary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
