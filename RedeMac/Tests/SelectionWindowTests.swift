import XCTest

@testable import Rede

/// DR-4 (Privacy): pins the pure, cursor-relative windowing for reply/edit rewrite context.
/// `SelectionContextService.surroundingWindow` must send only a window around the caret/selection
/// instead of the whole focused field. The AX read itself is not unit-tested — strings are built
/// directly and ranges follow AX `NSRange` (UTF-16) semantics.
@MainActor
final class SelectionWindowTests: XCTestCase {

  private let maxChars = 600

  // A plain ASCII corpus where each UTF-16 unit is one character — keeps offsets readable.
  private func corpus(_ count: Int) -> String {
    String((0..<count).map { Character(UnicodeScalar(UInt8(65 + $0 % 26))) })
  }

  // MARK: - Range in the middle → centered window

  func testRangeInMiddleReturnsCenteredWindow() {
    // Embed a unique marker at the selection site so we can locate it unambiguously
    // (the A–Z corpus repeats, so a generic substring would match earlier occurrences).
    let marker = "<<SELECTION>>"
    var text = corpus(5000)
    let insertAt = text.index(text.startIndex, offsetBy: 2500)
    text.insert(contentsOf: marker, at: insertAt)
    let selection = NSRange(location: 2500, length: marker.utf16.count)

    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: selection, maxChars: maxChars)

    XCTAssertEqual(window.utf16.count, maxChars)
    // The selection must sit inside the window, with text on both sides (roughly centered).
    XCTAssertTrue(window.contains(marker))
    let location = (window as NSString).range(of: marker).location
    XCTAssertGreaterThan(location, 100, "should keep context before the selection")
    XCTAssertLessThan(location, maxChars - 100, "should keep context after the selection")
  }

  // MARK: - Range near the start → window from start

  func testRangeNearStartReturnsWindowFromStart() {
    let text = corpus(5000)
    let selection = NSRange(location: 5, length: 3)
    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: selection, maxChars: maxChars)

    XCTAssertEqual(window.utf16.count, maxChars)
    // Short left side → window expands to the right and starts at the very beginning.
    XCTAssertTrue(text.hasPrefix(window))
  }

  // MARK: - Range near the end → window ending at end

  func testRangeNearEndReturnsWindowEndingAtEnd() {
    let text = corpus(5000)
    let selection = NSRange(location: 4990, length: 5)
    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: selection, maxChars: maxChars)

    XCTAssertEqual(window.utf16.count, maxChars)
    // Short right side → window expands to the left and ends at the very end.
    XCTAssertTrue(text.hasSuffix(window))
  }

  // MARK: - nil range → first maxChars (today's truncation fallback)

  func testNilRangeFallsBackToFirstMaxChars() {
    let text = corpus(5000)
    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: nil, maxChars: maxChars)

    XCTAssertEqual(window.utf16.count, maxChars)
    XCTAssertTrue(text.hasPrefix(window))
  }

  // MARK: - maxChars larger than text → whole text

  func testMaxCharsLargerThanTextReturnsWholeText() {
    let text = corpus(120)
    let selection = NSRange(location: 50, length: 4)
    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: selection, maxChars: maxChars)

    XCTAssertEqual(window, text)
  }

  // MARK: - Out-of-bounds range → safe fallback (no crash)

  func testOutOfBoundsRangeFallsBackSafely() {
    let text = corpus(5000)
    // location beyond the string → invalid → fall back to the first maxChars.
    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: NSRange(location: 99_999, length: 10), maxChars: maxChars)

    XCTAssertEqual(window.utf16.count, maxChars)
    XCTAssertTrue(text.hasPrefix(window))
  }

  func testRangeLengthRunningPastEndIsClampedNoCrash() {
    let text = corpus(700)
    // Valid start, but length runs past the end — must clamp, not crash.
    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: NSRange(location: 690, length: 500), maxChars: maxChars)

    XCTAssertEqual(window.utf16.count, maxChars)
    XCTAssertTrue(text.hasSuffix(window))
  }

  func testNotFoundLocationFallsBack() {
    let text = corpus(5000)
    let window = SelectionContextService.surroundingWindow(
      fullText: text, selectedRange: NSRange(location: NSNotFound, length: 0), maxChars: maxChars)

    XCTAssertEqual(window.utf16.count, maxChars)
    XCTAssertTrue(text.hasPrefix(window))
  }

  // MARK: - Empty input → empty output (no crash)

  func testEmptyTextReturnsEmpty() {
    let window = SelectionContextService.surroundingWindow(
      fullText: "", selectedRange: NSRange(location: 0, length: 0), maxChars: maxChars)
    XCTAssertTrue(window.isEmpty)
  }

  // MARK: - Privacy invariant: never exceed the budget

  func testNeverExceedsBudget() {
    let text = corpus(10_000)
    for location in stride(from: 0, to: 10_000, by: 777) {
      let window = SelectionContextService.surroundingWindow(
        fullText: text, selectedRange: NSRange(location: location, length: 12), maxChars: maxChars)
      XCTAssertLessThanOrEqual(window.utf16.count, maxChars)
    }
  }
}
