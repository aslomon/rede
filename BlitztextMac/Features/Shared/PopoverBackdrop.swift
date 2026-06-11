import AppKit
import SwiftUI

/// AppKit-backed `.popover`-material backdrop for the menu bar popover.
///
/// `NSPopover` draws its arrow ("Spitze") and frame in the system `.popover` material itself.
/// The macOS-26 `.glassEffect` backstop (`blitztextSurface`) only covered the SwiftUI body, so the
/// system-drawn arrow stayed a different shade — the visible background mismatch at the tip.
/// Rendering the body in the SAME `.popover` material makes body + arrow read as one surface.
struct PopoverBackdrop: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .popover
    view.state = .active
    view.blendingMode = .behindWindow
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = .popover
    nsView.state = .active
    nsView.blendingMode = .behindWindow
  }
}

extension View {
  /// Popover-only surface: the native `.popover` material so the SwiftUI body matches the
  /// NSPopover-drawn arrow exactly. Use ONLY on the popover root (`MenuBarView`) — windows and the
  /// floating pill keep their own surfaces.
  func popoverSurface() -> some View {
    background(PopoverBackdrop().ignoresSafeArea())
  }
}
