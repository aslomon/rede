import AppKit
import SwiftUI

/// Hosts the full `ArchiveWindowView` in a standalone, resizable window. The 340pt menu-bar popover
/// only shows a condensed preview of the newest entries; the complete day-grouped archive gets its
/// own window. Created by `AppDelegate`; opened on the `.openArchiveWindow` notification.
@MainActor
final class ArchiveWindowController {
  private let appState: AppState
  private var window: NSWindow?

  init(appState: AppState) {
    self.appState = appState
  }

  /// Show (creating on first use) and focus the window.
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

  private func makeWindow() -> NSWindow {
    let hosting = NSHostingController(rootView: ArchiveWindowView(appState: appState))
    let window = NSWindow(contentViewController: hosting)
    window.title = "rede archiv"
    // Transparent, full-size-content title bar so the content runs to the top with no separator line;
    // the traffic lights float over the content (matches the onboarding window).
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.titlebarSeparatorStyle = .none  // removes the hairline separator under the title bar
    window.isMovableByWindowBackground = true
    window.setContentSize(NSSize(width: 520, height: 620))
    window.minSize = NSSize(width: 460, height: 420)
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }
}
