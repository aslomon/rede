import AppKit
import SwiftUI

/// "Sauber Entfernen": prepares this Mac for deleting rede — removes the login item and,
/// optionally, local data. Self-contained confirm flow so the System tab stays small.
struct CleanupSection: View {
  @State private var launchAtLoginService = LaunchAtLoginService()
  @State private var showCleanupOptions = false
  @State private var deleteLocalDataOnCleanup = true
  @State private var cleanupStatusText: String?
  @State private var cleanupErrorText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: "Sauber Entfernen")

      Text(
        "Vor dem Löschen rede erst auf diesem Mac bereinigen. So verschwinden Anmeldestart und lokale Daten sauber aus dem Weg."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if showCleanupOptions {
        confirmControls
      } else {
        Button("Entfernung vorbereiten") {
          showCleanupOptions = true
        }
        .buttonStyle(PopoverActionButtonStyle(.danger))
      }

      if let cleanupStatusText {
        Text(cleanupStatusText)
          .font(.system(size: 10.5))
          .foregroundStyle(.green)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let cleanupErrorText {
        Text(cleanupErrorText)
          .font(.system(size: 10.5))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var confirmControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(
        "Zugangsdaten und Einstellungen dieses Macs löschen", isOn: $deleteLocalDataOnCleanup
      )
      .toggleStyle(.switch)
      .controlSize(.small)

      Text(
        "Danach rede beenden und die App aus /Applications löschen. Bereits verwaiste alte Login-Items können in den Systemeinstellungen einmalig manuell entfernt werden."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Button("Abbrechen") {
          showCleanupOptions = false
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))

        Button("Jetzt bereinigen") {
          runCleanup()
        }
        .buttonStyle(PopoverActionButtonStyle(.danger))
      }
    }
  }

  private func runCleanup() {
    cleanupStatusText = nil
    cleanupErrorText = nil

    let report =
      deleteLocalDataOnCleanup
      ? BlitztextCleanupService.cleanupUserData()
      : BlitztextCleanupService.removeLaunchAtLoginRegistration()

    KeychainService.invalidateCache()
    launchAtLoginService.refresh()

    if report.failedItems.isEmpty {
      cleanupStatusText =
        deleteLocalDataOnCleanup
        ? "Anmeldestart und lokale Daten wurden bereinigt. Jetzt rede beenden und aus /Applications löschen."
        : "Anmeldestart wurde deaktiviert. Jetzt rede beenden und aus /Applications löschen."
      showCleanupOptions = false

      let urlsToReveal =
        report.knownInstallBundleURLs.isEmpty
        ? [BlitztextInstallLocationService.bundleURL]
        : report.knownInstallBundleURLs
      revealInFinder(urls: urlsToReveal)
      return
    }

    let failureSummary = report.failedItems
      .map { "\($0.url.lastPathComponent): \($0.errorDescription)" }
      .joined(separator: "\n")
    cleanupErrorText = "Nicht alles konnte bereinigt werden:\n\(failureSummary)"
  }

  private func revealInFinder(urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }
}
