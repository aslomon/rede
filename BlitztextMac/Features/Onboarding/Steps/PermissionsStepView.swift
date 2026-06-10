import SwiftUI

/// Step: microphone + accessibility permissions. Both are soft-warned — the wizard always lets
/// the user continue, it just shows a coloured hint while a grant is still missing.
struct PermissionsStepView: View {
  @Bindable var appState: AppState
  @State private var micStatus = MicrophonePermissionService.currentStatus

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingStepHeader(
        systemImage: "hand.raised.fill",
        accent: .orange,
        title: "berechtigungen",
        subtitle: "mikrofon nimmt auf. bedienungshilfen fügen direkt ein."
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
        SectionLabel(text: "mikrofon")

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
          InfoDisclosure("warum") {
            Text(micStatusDetail)
          }
        }

        // Primary grant action (only shown when not yet granted) (change 11)
        HStack(spacing: 8) {
          if micStatus == .notDetermined {
            Button("mikrofon erlauben") { requestMicrophone() }
              .buttonStyle(PopoverActionButtonStyle(.warning))
          } else if micStatus == .denied {
            Button("in systemeinstellungen öffnen") {
              MicrophonePermissionService.openSystemSettings()
            }
            .buttonStyle(PopoverActionButtonStyle(.warning))
          }

          // 'erneut prüfen' hidden when already granted; rendered as subordinate icon-button
          // when not granted (change 11)
          if !micStatus.isGranted {
            Button {
              micStatus = MicrophonePermissionService.currentStatus
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PopoverIconButtonStyle(.quiet))
            .help("status aktualisieren")
          }
        }
      }
    }
  }

  private var micStatusTitle: String {
    switch micStatus {
    case .granted: return "läuft — mikrofon ist erlaubt"
    case .denied: return "blockiert"
    case .notDetermined: return "noch nicht erteilt"
    }
  }

  private var micStatusDetail: String {
    switch micStatus {
    case .granted:
      return "aufnehmen ist freigegeben."
    case .denied:
      return
        "macOS hat das mikrofon blockiert. erlaube rede in den systemeinstellungen unter datenschutz → mikrofon."
    case .notDetermined:
      return "rede braucht das mikrofon zum aufnehmen deiner stimme."
    }
  }

  private func requestMicrophone() {
    Task {
      micStatus = await MicrophonePermissionService.request()
    }
  }
}
