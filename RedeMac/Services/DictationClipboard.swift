import AppKit

/// Final dictation output stays available for manual reuse after every delivery attempt.
@MainActor
struct DictationClipboard {
  let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func copy(_ text: String) {
    ArchiveClipboard.copyConcealed(text, pasteboard: pasteboard)
  }

  /// The target consumes the same clipboard output that remains available for later Cmd+V.
  func paste() {
    paste(using: Self.sendPasteCommand)
  }

  func paste(using command: @MainActor () -> Void) {
    command()
  }

  private static func sendPasteCommand() {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }
}
