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
      SectionLabel(text: "bedienungshilfen", icon: "accessibility")

      BlitzStatusPill(state: isGranted ? .ready : .warning, label: isGranted ? "erkannt" : "fehlt")

      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            isGranted
              ? "direktes einfügen ist freigegeben."
              : "direktes einfügen ist noch nicht freigegeben."
          )
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)

          if !isGranted {
            // The remove-and-re-add path must be reachable here too, not only via the
            // stale-grant banner: a FRESH install (hadAccessibilityGrant == false) hits the
            // same dead end when macOS shows the toggle as on for an outdated entry.
            InfoDisclosure("hilfe") {
              VStack(alignment: .leading, spacing: 4) {
                Text("öffne bedienungshilfen und aktiviere rede.")
                Text(
                  "sieht der schalter schon aktiv aus, wird aber nicht erkannt: den "
                    + "rede-eintrag mit dem minus (−) entfernen und neu hinzufügen. das "
                    + "passiert vor allem nach updates oder neubauten der app."
                )
              }
            }
          }
        }
      }

      if isStale {
        staleGrantHint
      }

      // Button hierarchy:
      // • isGranted == true:  'bedienungshilfen öffnen' → .quiet (demoted, already done)
      //                       'erneut prüfen' → .secondary
      // • isGranted == false: 'bedienungshilfen öffnen' → .warning (sole primary CTA)
      //                       'erneut prüfen' as icon button (.quiet), not a full label button
      if isGranted {
        HStack(spacing: 8) {
          Button {
            appState.requestAccessibilityPermission()
          } label: {
            Label("bedienungshilfen öffnen", systemImage: "arrow.up.forward.app")
          }
          .buttonStyle(PopoverActionButtonStyle(.quiet))

          Button {
            appState.refreshAccessibilityPermission()
          } label: {
            Label("erneut prüfen", systemImage: "arrow.clockwise")
          }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
        }
      } else {
        HStack(spacing: 8) {
          Button {
            appState.requestAccessibilityPermission()
          } label: {
            Label("bedienungshilfen öffnen", systemImage: "arrow.up.forward.app")
          }
          .buttonStyle(PopoverActionButtonStyle(.warning))

          Button {
            appState.refreshAccessibilityPermission()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(PopoverIconButtonStyle(.quiet))
          .accessibilityLabel("Erneut prüfen")
          .help("erneut prüfen")
        }
      }
    }
  }

  /// Targeted copy for the stale-grant case: after an update macOS may still show rede as
  /// enabled but no longer recognize it. The fix is to remove the entry with the minus and re-add.
  /// Uses the flat .tintBanner(.orange) — this hint nests inside cards (DESIGN.md).
  private var staleGrantHint: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.orange)
          .frame(width: 16, height: 16)

        VStack(alignment: .leading, spacing: 3) {
          Text("freigabe wird nicht mehr erkannt.")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary)

          Text(
            "nach einem update kann macOS rede unter bedienungshilfen noch als aktiviert anzeigen, ohne es wirklich zu erkennen. so behebst du das einmalig:"
          )
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        staleStep(number: "1", text: "bedienungshilfen öffnen.")
        staleStep(
          number: "2",
          text:
            "den vorhandenen rede-eintrag in der liste auswählen und mit dem minus (−) entfernen."
        )
        staleStep(
          number: "3",
          text: "rede erneut hinzufügen bzw. den schalter wieder einschalten.")
      }
      .padding(.leading, 24)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    // Flat tint — this section renders inside settings cards and onboarding cards (DESIGN.md).
    .tintBanner(.orange)
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
