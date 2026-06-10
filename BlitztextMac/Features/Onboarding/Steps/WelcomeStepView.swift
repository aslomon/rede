import SwiftUI

/// Step 1: a warm intro with three value bullets and (when applicable) the "move to /Applications"
/// nudge carried over from the old in-popover onboarding.
struct WelcomeStepView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingStepHeader(
        systemImage: "sparkles",
        accent: .blue,
        title: "Willkommen bei rede",
        subtitle: "Einmal einrichten. Danach sprechen, loslassen, Text sitzt im Feld."
      )

      VStack(alignment: .leading, spacing: 10) {
        valueBullet(
          icon: "mic.fill", accent: .blue,
          title: "Sprechen statt tippen",
          detail: "Hotkey halten, sprechen, loslassen.")
        valueBullet(
          icon: "text.badge.checkmark", accent: .purple,
          title: "Fertig formuliert",
          detail: "E-Mail, Prompt oder Social aus deinem Diktat.")
        valueBullet(
          icon: "lock.shield.fill", accent: .green,
          title: "Online oder komplett lokal",
          detail: "Du entscheidest, wo Verarbeitung läuft.")
      }
    }
  }

  private func valueBullet(icon: String, accent: Color, title: String, detail: String)
    -> some View
  {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(.primary)
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

}
