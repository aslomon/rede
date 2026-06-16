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
      SectionLabel(text: "sauber entfernen", icon: "trash")

      Text(
        "vor dem löschen rede erst auf diesem Mac bereinigen. so verschwinden anmeldestart und lokale daten sauber aus dem weg."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if showCleanupOptions {
        confirmControls
      } else {
        Button {
          showCleanupOptions = true
        } label: {
          Label("entfernung vorbereiten", systemImage: "trash")
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
      Toggle(isOn: $deleteLocalDataOnCleanup) {
        Label("zugangsdaten und einstellungen dieses Macs löschen", systemImage: "key.fill")
          .labelStyle(QuietToggleLabelStyle())
      }
      .toggleStyle(.switch)
      .controlSize(.small)

      Text(
        "danach rede beenden und die app aus /Applications löschen. bereits verwaiste alte login-items können in den systemeinstellungen einmalig manuell entfernt werden."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Button("abbrechen") {
          showCleanupOptions = false
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))

        Button {
          runCleanup()
        } label: {
          Label("jetzt bereinigen", systemImage: "trash")
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
      ? RedeCleanupService.cleanupUserData()
      : RedeCleanupService.removeLaunchAtLoginRegistration()

    KeychainService.invalidateCache()
    launchAtLoginService.refresh()

    if report.failedItems.isEmpty {
      cleanupStatusText =
        deleteLocalDataOnCleanup
        ? "anmeldestart und lokale daten wurden bereinigt. jetzt rede beenden und aus /Applications löschen."
        : "anmeldestart wurde deaktiviert. jetzt rede beenden und aus /Applications löschen."
      showCleanupOptions = false

      let urlsToReveal =
        report.knownInstallBundleURLs.isEmpty
        ? [RedeInstallLocationService.bundleURL]
        : report.knownInstallBundleURLs
      revealInFinder(urls: urlsToReveal)
      return
    }

    let failureSummary = report.failedItems
      .map { "\($0.url.lastPathComponent): \($0.errorDescription)" }
      .joined(separator: "\n")
    cleanupErrorText = "nicht alles konnte bereinigt werden:\n\(failureSummary)"
  }

  private func revealInFinder(urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }
}
