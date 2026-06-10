import AppKit
import SwiftUI

/// Step 2: installation location. This is its own setup step so the user sees a clear status and a
/// concrete action instead of a paragraph inside the welcome screen.
struct InstallLocationStepView: View {
  @State private var currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
  @State private var errorText: String?

  private var isInApplications: Bool {
    currentInstallLocation == .applications
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingStepHeader(
        systemImage: "arrow.down.app",
        accent: isInApplications ? .green : .orange,
        title: "speicherort",
        subtitle: "eine app-kopie in /Applications hält start, updates und hotkeys sauber."
      )

      OnboardingCard(accent: isInApplications ? nil : .orange) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            BlitzStatusPill(
              state: isInApplications ? .ready : .warning,
              label: isInApplications ? "sitzt" : "verschieben"
            )
            Text(headline)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(.primary)
            Spacer(minLength: 0)
          }

          Text(BlitztextInstallLocationService.bundleURL.path)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)

          HStack(spacing: 8) {
            if BlitztextInstallLocationService.shouldOfferMoveToApplications {
              Button {
                moveToApplications()
              } label: {
                Label("nach /Applications bewegen", systemImage: "arrow.down.app.fill")
              }
              .buttonStyle(PopoverActionButtonStyle(.warning))
            }

            Button {
              revealInFinder(urls: [BlitztextInstallLocationService.bundleURL])
            } label: {
              Label("im Finder zeigen", systemImage: "finder")
            }
            .buttonStyle(PopoverActionButtonStyle(.secondary))
          }

          if let errorText {
            Text(errorText)
              .font(.system(size: 10.5))
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
        OnboardingCard(accent: .orange) {
          VStack(alignment: .leading, spacing: 8) {
            BlitzStatusPill(state: .warning, label: "mehrere kopien")
            Text("weitere rede-kopien können doppelte login-items auslösen.")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
            Button {
              revealInFinder(urls: BlitztextInstallLocationService.otherInstalledBundleURLs)
            } label: {
              Label("weitere kopien zeigen", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(PopoverActionButtonStyle(.warning))
          }
        }
      }
    }
  }

  private var headline: String {
    isInApplications ? "rede liegt am richtigen ort." : "rede liegt noch nicht in /Applications."
  }

  private func moveToApplications() {
    errorText = nil
    do {
      try BlitztextInstallLocationService.moveToApplicationsAndRelaunch()
    } catch {
      errorText = error.localizedDescription
    }
    currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
  }

  private func revealInFinder(urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }
}
