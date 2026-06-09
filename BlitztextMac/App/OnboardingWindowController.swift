import AppKit
import SwiftUI

/// Hosts the first-run `OnboardingWizardView` in a standalone, resizable window — the 340pt popover
/// is far too narrow for the 6-step wizard. Mirrors `LocalModelsWindowController`. Created by
/// `AppDelegate`; opened on the `.openOnboardingWindow` notification and on launch when onboarding
/// has not been completed. Closing the window early (without "Fertig") keeps the launch nudge.
@MainActor
final class OnboardingWindowController {
  private let appState: AppState
  /// Invoked when the wizard asks to jump into the full popover settings (after finishing).
  private let onOpenSettings: () -> Void
  private var window: NSWindow?

  init(appState: AppState, onOpenSettings: @escaping () -> Void) {
    self.appState = appState
    self.onOpenSettings = onOpenSettings
  }

  /// Show (creating on first use), center, and focus the window.
  func show() {
    if window == nil {
      window = makeWindow()
    }
    guard let window else { return }
    window.makeKeyAndOrderFront(nil)
    if !window.isVisible || window.frame.origin == .zero {
      window.center()
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private func close() {
    window?.performClose(nil)
  }

  private func makeWindow() -> NSWindow {
    let rootView = OnboardingWizardView(
      appState: appState,
      onClose: { [weak self] in self?.close() },
      onOpenSettings: { [weak self] in
        self?.close()
        self?.onOpenSettings()
      }
    )
    let hosting = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hosting)
    window.title = "Blitztext einrichten"
    // Modern macOS look: transparent, full-size-content title bar so the glass surface runs to the
    // very top edge and the traffic lights float over the content, instead of an opaque title band
    // sitting above every step.
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.titlebarSeparatorStyle = .none  // removes the hairline separator under the title bar
    window.isMovableByWindowBackground = true
    window.setContentSize(NSSize(width: 620, height: 560))
    window.minSize = NSSize(width: 560, height: 520)
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }
}
