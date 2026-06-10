import SwiftUI

/// Step 1: a warm intro with three value bullets and (when applicable) the "move to /Applications"
/// nudge carried over from the old in-popover onboarding.
struct WelcomeStepView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingStepHeader(
        systemImage: "sparkles",
        accent: .blue,
        title: "lass uns reden",
        subtitle: "Einmal einrichten — danach: sprechen, loslassen, Text sitzt im Feld."
      )

      VStack(alignment: .leading, spacing: 10) {
        valueBullet(
          icon: "mic.fill", accent: .blue,
          title: "sprechen statt tippen",
          detail: "hotkey halten, einfach reden, loslassen. fertig.")
        valueBullet(
          icon: "text.badge.checkmark", accent: .purple,
          title: "kommt fertig formuliert raus",
          detail: "e-mail, prompt oder social — direkt aus deinem diktat.")
        valueBullet(
          icon: "lock.shield.fill", accent: .green,
          title: "online oder komplett lokal",
          detail: "du entscheidest, wo's läuft. lokal bleibt alles auf deinem mac.")
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
