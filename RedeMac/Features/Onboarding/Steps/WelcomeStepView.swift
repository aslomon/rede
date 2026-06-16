import SwiftUI

/// Welcome step: three value bullets plus the one personal question — your name. The headline
/// ("lass uns reden.") lives in the wizard hero; this body carries only the controls.
struct WelcomeStepView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
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
          detail: "du entscheidest, wo's läuft. lokal bleibt alles auf deinem Mac.")
      }

      nameCard
    }
  }

  /// The single decision on this step: the user's name. It becomes the fixed writing perspective
  /// ("Ich schreibe als …") for rewrite prompts and a speech-recognition spelling hint.
  private var nameCard: some View {
    OnboardingCard(accent: .blue) {
      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "wie heißt du?", icon: "person.crop.circle")

        TextField("dein name", text: $appState.appSettings.userDisplayName)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 13))

        Text(
          "wird deine schreibperspektive („Ich schreibe als …“) und hilft der spracherkennung, "
            + "deinen namen richtig zu schreiben. bleibt lokal in deinen einstellungen."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
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
