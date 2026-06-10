import AppKit
import SwiftUI

/// Hosts the `LocalModelsView` in a standalone, resizable window. The 340pt menu-bar popover is too
/// narrow for the model catalog (sizes, RAM, progress), so model management gets its own window.
/// Created by `AppDelegate`; opened on the `.openLocalModelsWindow` notification.
@MainActor
final class LocalModelsWindowController {
  private let appState: AppState
  private let manager: LocalModelManager
  private var window: NSWindow?

  init(appState: AppState, manager: LocalModelManager) {
    self.appState = appState
    self.manager = manager
  }

  /// Show (creating on first use) and focus the window, then refresh its data.
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
    Task { await manager.refresh() }
  }

  private func makeWindow() -> NSWindow {
    let hosting = NSHostingController(
      rootView: LocalModelsView(appState: appState, manager: manager))
    let window = NSWindow(contentViewController: hosting)
    window.title = "rede modelle"
    // Transparent, full-size-content title bar so the content runs to the top with no separator line;
    // the traffic lights float over the content (matches the onboarding window).
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.titlebarSeparatorStyle = .none  // removes the hairline separator under the title bar
    window.isMovableByWindowBackground = true
    window.setContentSize(NSSize(width: 560, height: 660))
    window.minSize = NSSize(width: 520, height: 480)
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }
}
