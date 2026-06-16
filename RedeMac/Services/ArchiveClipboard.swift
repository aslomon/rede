import AppKit

// MARK: - Concealed clipboard copy (FT-3 "Archiv wiederverwenden")

/// Copies archive text to the general pasteboard the SAME way the dictation paste path does:
/// it also marks the item with `org.nspasteboard.ConcealedType` so clipboard-history tools treat
/// the (potentially sensitive) transcript as transient and don't persist it. No-op for empty text.
enum ArchiveClipboard {
  static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

  static func copyConcealed(_ text: String, pasteboard: NSPasteboard = .general) {
    guard !text.isEmpty else { return }
    pasteboard.clearContents()
    pasteboard.declareTypes([.string, concealedType], owner: nil)
    pasteboard.setString(text, forType: .string)
    pasteboard.setString("", forType: concealedType)
  }
}
