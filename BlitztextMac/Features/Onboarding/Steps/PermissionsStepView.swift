import SwiftUI

/// Step 2: microphone + accessibility permissions. Both are soft-warned — the wizard always lets
/// the user continue, it just shows a coloured hint while a grant is still missing.
struct PermissionsStepView: View {
  @Bindable var appState: AppState
  @State private var micStatus = MicrophonePermissionService.currentStatus

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingStepHeader(
        systemImage: "hand.raised.fill",
        accent: .orange,
        title: "Berechtigungen",
        subtitle: "Mikrofon nimmt auf. Bedienungshilfen fügen direkt ein."
      )

      microphoneCard

      OnboardingCard {
        AccessibilityPermissionSection(appState: appState)
      }
    }
    .onAppear { micStatus = MicrophonePermissionService.currentStatus }
  }

  private var microphoneCard: some View {
    OnboardingCard(accent: micStatus.isGranted ? nil : .orange) {
      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "Mikrofon")

        HStack(spacing: 6) {
          Image(
            systemName: micStatus.isGranted
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(micStatus.isGranted ? .green : .orange)
          .frame(width: 16, height: 16)

          Text(micStatusTitle)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary)
        }

        if !micStatus.isGranted {
          InfoDisclosure("Warum") {
            Text(micStatusDetail)
          }
        }

        // Primary grant action (only shown when not yet granted) (change 11)
        HStack(spacing: 8) {
          if micStatus == .notDetermined {
            Button("Mikrofon erlauben") { requestMicrophone() }
              .buttonStyle(PopoverActionButtonStyle(.warning))
          } else if micStatus == .denied {
            Button("In Einstellungen öffnen") {
              MicrophonePermissionService.openSystemSettings()
            }
            .buttonStyle(PopoverActionButtonStyle(.warning))
          }

          // 'Erneut prüfen' hidden when already granted; rendered as subordinate icon-button
          // when not granted (change 11)
          if !micStatus.isGranted {
            Button {
              micStatus = MicrophonePermissionService.currentStatus
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PopoverIconButtonStyle(.quiet))
            .help("Status aktualisieren")
          }
        }
      }
    }
  }

  private var micStatusTitle: String {
    switch micStatus {
    case .granted: return "Status: erlaubt"
    case .denied: return "Status: blockiert"
    case .notDetermined: return "Status: noch nicht erteilt"
    }
  }

  private var micStatusDetail: String {
    switch micStatus {
    case .granted:
      return "Aufnehmen ist freigegeben."
    case .denied:
      return
        "macOS hat das Mikrofon blockiert. Erlaube rede in den Systemeinstellungen unter Datenschutz → Mikrofon."
    case .notDetermined:
      return "rede braucht das Mikrofon zum Aufnehmen deiner Stimme."
    }
  }

  private func requestMicrophone() {
    Task {
      micStatus = await MicrophonePermissionService.request()
    }
  }
}
