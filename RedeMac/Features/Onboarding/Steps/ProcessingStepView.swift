import SwiftUI

/// Step: choose where transcription and rewriting happen. Local is the first-run default; online
/// (OpenAI) reveals the key entry.
struct ProcessingStepView: View {
  @Bindable var appState: AppState
  @Environment(\.colorScheme) private var colorScheme

  private var isLocal: Bool { appState.appSettings.secureLocalModeEnabled }

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      VStack(spacing: 10) {
        choiceCard(
          selected: isLocal,
          icon: "lock.shield.fill",
          accent: .green,
          pillState: .local,
          title: "sicherer lokaler modus",
          detail: "alles bleibt auf diesem Mac. kein server, keine cloud. lokale modelle nötig."
        ) {
          appState.appSettings.secureLocalModeEnabled = true
        }

        choiceCard(
          selected: !isLocal,
          icon: "cloud",
          accent: .blue,
          pillState: .online,
          title: "online (OpenAI)",
          detail:
            "schnell und stark. audio und text gehen an die OpenAI-API. eigener API-Key nötig."
        ) {
          appState.appSettings.secureLocalModeEnabled = false
        }
      }

      if isLocal {
        offlineAssurance
      } else {
        OnboardingCard {
          OpenAIKeySection(appState: appState)
        }
      }
    }
  }

  private func choiceCard(
    selected: Bool,
    icon: String,
    accent: Color,
    pillState: RedeStatusPill.State,
    title: String,
    detail: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 14))
          .foregroundStyle(selected ? accent : .secondary)
          .frame(width: 18, height: 18)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Image(systemName: icon)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(accent)
            Text(title)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(.primary)
            if selected {
              RedeStatusPill(state: pillState, label: "gewählt")
            }
          }
          Text(detail)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      // MenuBarTokens fills keep the selected state legible in dark mode (raw accent.opacity
      // collapsed to near-invisible there).
      .background(
        RoundedRectangle(cornerRadius: OnboardingChrome.cardCornerRadius)
          .fill(
            selected
              ? MenuBarTokens.tintFill(accent, colorScheme: colorScheme)
              : MenuBarTokens.cardFill(colorScheme: colorScheme).opacity(0.4)
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: OnboardingChrome.cardCornerRadius)
          .strokeBorder(
            selected
              ? MenuBarTokens.tintStroke(accent, colorScheme: colorScheme)
              : MenuBarTokens.cardStroke(colorScheme: colorScheme),
            lineWidth: selected ? 1 : 0.5
          )
      )
    }
    .buttonStyle(.plain)
    .help(title)
  }

  private var offlineAssurance: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "checkmark.shield.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.green)
        .frame(width: 16, height: 16)
      Text(
        "offline aktiv: deine aufnahmen verlassen diesen Mac nicht. im nächsten schritt lädst du das lokale Whisper-Modell."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }
}
