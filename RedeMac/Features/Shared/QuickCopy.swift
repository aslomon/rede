import SwiftUI

// MARK: - Shared copy-feedback language

/// The app-wide copy-feedback glyph: a neutral `doc.on.doc` that swaps to a green
/// `checkmark.circle.fill` while `copied` is true. Stateless — the caller owns the `copied` flag.
///
/// The non-copied color is inherited from the surrounding context (`ShapeStyle.foreground`), so a
/// parent can brighten it on hover or the button style can tint it; the copied state is always
/// green. It is a plain conditional swap with a 0.15 s ease — deliberately no `symbolEffect`, so it
/// compiles and runs on macOS 14.
struct QuickCopyGlyph: View {
  let copied: Bool

  var body: some View {
    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
      .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.foreground))
      .animation(.easeInOut(duration: 0.15), value: copied)
  }
}

// MARK: - Archive quick-copy button

/// A ~28 pt icon button that copies `text` to the clipboard the concealed way and briefly confirms
/// with the shared `QuickCopyGlyph`. Used on collapsed archive rows (standalone window + Settings
/// inline preview). Owns its own `copied` state with a guarded 1.5 s reset that re-arms on re-tap.
struct ArchiveQuickCopyButton: View {
  let text: String
  var accessibilityLabel: String = "endtext kopieren"

  @State private var copied = false
  @State private var resetTask: Task<Void, Never>?

  var body: some View {
    Button {
      ArchiveClipboard.copyConcealed(text)
      confirmCopy()
    } label: {
      QuickCopyGlyph(copied: copied)
    }
    .buttonStyle(PopoverIconButtonStyle(.quiet))
    .help("kopieren")
    .disabled(text.isEmpty)
    .accessibilityLabel(accessibilityLabel)
  }

  private func confirmCopy() {
    copied = true
    // Announce for VoiceOver — the visual swap alone is not audible.
    AccessibilityNotification.Announcement("kopiert").post()

    resetTask?.cancel()
    resetTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      guard !Task.isCancelled else { return }
      copied = false
    }
  }
}
