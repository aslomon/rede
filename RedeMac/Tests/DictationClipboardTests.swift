import AppKit
import XCTest

@testable import Rede

@MainActor
final class DictationClipboardTests: XCTestCase {
  func testPasteReadsFinalOutputAndKeepsItAvailable() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("previous clipboard", forType: .string)
    let clipboard = DictationClipboard(pasteboard: pasteboard)
    clipboard.copy("Final dictation")
    var pastedText: String?

    clipboard.paste {
      pastedText = pasteboard.string(forType: .string)
    }
    try await Task.sleep(for: .seconds(1))

    XCTAssertEqual(pastedText, "Final dictation")
    XCTAssertEqual(pasteboard.string(forType: .string), "Final dictation")
    XCTAssertTrue(pasteboard.types?.contains(ArchiveClipboard.concealedType) == true)
  }

  func testCopyWithoutPasteKeepsFallbackAvailable() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let clipboard = DictationClipboard(pasteboard: pasteboard)

    clipboard.copy("Manual paste fallback")

    XCTAssertEqual(pasteboard.string(forType: .string), "Manual paste fallback")
  }

  func testLaterUserCopyIsNeverReplacedByDelayedRestore() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let clipboard = DictationClipboard(pasteboard: pasteboard)
    clipboard.copy("First dictation")
    clipboard.paste {}
    clipboard.copy("Second dictation")
    clipboard.paste {}
    pasteboard.clearContents()
    pasteboard.setString("User copied something else", forType: .string)
    try await Task.sleep(for: .seconds(1))

    XCTAssertEqual(pasteboard.string(forType: .string), "User copied something else")
  }
}
