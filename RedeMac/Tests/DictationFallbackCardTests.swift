import AppKit
import SwiftUI
import XCTest

@testable import Rede

@MainActor
final class DictationFallbackCardTests: XCTestCase {
  func testFallbackCardRendersBoundedPreviewInBothAppearances() throws {
    let sample = String(repeating: "Das ist ein Beispieldiktat für die Zwischenablage. ", count: 12)
    for scheme in [ColorScheme.light, .dark] {
      let card = DictationFallbackCard(text: sample, onCopy: { _ in }, onDismiss: {})
        .environment(\.colorScheme, scheme)
        .padding(24)
        .background(scheme == .light ? Color.white : Color.black)
      let hostingView = NSHostingView(rootView: card)
      hostingView.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
      hostingView.layoutSubtreeIfNeeded()
      XCTAssertEqual(hostingView.frame.width, LiquidGlass.pillExpandedWidth + 48)
      XCTAssertLessThan(hostingView.frame.height, 400)
      let bitmap = try XCTUnwrap(
        hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
      hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
      let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      let appearance = scheme == .light ? "light" : "dark"
      try data.write(
        to: FileManager.default.temporaryDirectory
          .appendingPathComponent("rede-fallback-\(appearance).png"))
    }
  }
}
