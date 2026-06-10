import SwiftUI

// MARK: - Accessibility Permission Section

/// Bedienungshilfen-Status + Freigabe-Hilfe. Zeigt einen expliziten "erkannt / nicht erkannt"-
/// Status und — wenn die Freigabe nach einem Update als veraltet erkannt wird — gezielte Hinweise
/// zum einmaligen Entfernen und neu Hinzufuegen des rede-Eintrags.
struct AccessibilityPermissionSection: View {
  @Bindable var appState: AppState

  @Environment(\.colorScheme) private var colorScheme

  private var isGranted: Bool { appState.accessibilityPermissionGranted }
  private var isStale: Bool { appState.accessibilityLikelyStale }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Bedienungshilfen")

      BlitzStatusPill(state: isGranted ? .ready : .warning, label: isGranted ? "Erkannt" : "Fehlt")

      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            isGranted
              ? "Direktes Einfügen ist freigegeben."
              : "Direktes Einfügen ist noch nicht freigegeben."
          )
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)

          if !isGranted {
            InfoDisclosure("Hilfe") {
              Text(
                "Öffne Bedienungshilfen und aktiviere rede. Falls rede schon aktiv ist, einmal aus- und wieder einschalten."
              )
            }
          }
        }
      }

      if isStale {
        staleGrantHint
      }

      // Button hierarchy:
      // • isGranted == true:  'Bedienungshilfen öffnen' → .quiet (demoted, already done)
      //                       'Erneut prüfen' → .secondary
      // • isGranted == false: 'Bedienungshilfen öffnen' → .warning (sole primary CTA)
      //                       'Erneut prüfen' as icon button (.quiet), not a full label button
      if isGranted {
        HStack(spacing: 8) {
          Button("Bedienungshilfen öffnen") {
            appState.requestAccessibilityPermission()
          }
          .buttonStyle(PopoverActionButtonStyle(.quiet))

          Button("Erneut prüfen") {
            appState.refreshAccessibilityPermission()
          }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
        }
      } else {
        HStack(spacing: 8) {
          Button("Bedienungshilfen öffnen") {
            appState.requestAccessibilityPermission()
          }
          .buttonStyle(PopoverActionButtonStyle(.warning))

          Button {
            appState.refreshAccessibilityPermission()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(PopoverIconButtonStyle(.quiet))
          .accessibilityLabel("Erneut prüfen")
          .help("Erneut prüfen")
        }
      }
    }
  }

  /// Targeted copy for the stale-grant case: after an update macOS may still show rede as
  /// enabled but no longer recognize it. The fix is to remove the entry with the minus and re-add.
  /// Uses .liquidGlassInfoBanner(accent: .orange) for consistent banner styling.
  private var staleGrantHint: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.orange)
          .frame(width: 16, height: 16)

        VStack(alignment: .leading, spacing: 3) {
          Text("Freigabe wird nicht mehr erkannt.")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary)

          Text(
            "Nach einem Update kann macOS rede unter Bedienungshilfen noch als aktiviert anzeigen, ohne es wirklich zu erkennen. So behebst du das einmalig:"
          )
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        staleStep(number: "1", text: "Bedienungshilfen öffnen.")
        staleStep(
          number: "2",
          text:
            "Den vorhandenen rede-Eintrag in der Liste auswählen und mit dem Minus (−) entfernen."
        )
        staleStep(
          number: "3",
          text: "rede erneut hinzufügen bzw. den Schalter wieder einschalten.")
      }
      .padding(.leading, 24)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassInfoBanner(accent: .orange)
  }

  private func staleStep(number: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(number + ".")
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 14, alignment: .leading)
      Text(text)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
