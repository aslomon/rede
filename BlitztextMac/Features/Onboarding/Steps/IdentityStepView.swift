import SwiftUI

struct IdentityStepView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      // Moved 'bleibt lokal' assurance into the header subtitle (change 9)
      OnboardingStepHeader(
        systemImage: "person.text.rectangle",
        accent: .indigo,
        title: "Deine Schreibperspektive",
        subtitle:
          "rede nutzt deinen Namen als \u{201E}Ich schreibe als \u{2026}\u{201C}-Kontext in E-Mail- und Rewrite-Prompts. Bleibt lokal in deinen Einstellungen."
      )

      OnboardingCard(accent: .indigo) {
        VStack(alignment: .leading, spacing: 10) {
          TextField("Dein Name", text: $appState.appSettings.userDisplayName)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))

          // One concise 10.5pt hint about what the name is used for (change 9)
          Text("Hilft auch der Spracherkennung, deinen Namen korrekt zu schreiben.")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}
