import XCTest

@testable import Rede

@MainActor
final class RecentDictationsBufferTests: XCTestCase {

  func testRecordKeepsNewestFirstAndTruncatesToCap() {
    let buffer = RecentDictationsBuffer()
    let first = dictation(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let second = dictation(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let third = dictation(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
    let fourth = dictation(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

    buffer.record(first)
    buffer.record(second)
    buffer.record(third)
    buffer.record(fourth)

    XCTAssertEqual(buffer.items.map(\.id), [fourth.id, third.id, second.id])
    XCTAssertEqual(buffer.items.count, RecentDictationsBuffer.cap)
  }

  func testRecordDropsEmptyAndWhitespaceOnlyFinalText() {
    let buffer = RecentDictationsBuffer()

    buffer.record(dictation(text: ""))
    buffer.record(dictation(text: "   \n\t  "))

    XCTAssertTrue(buffer.items.isEmpty)
  }

  func testClearRemovesRecordedItems() {
    let buffer = RecentDictationsBuffer()
    buffer.record(dictation(text: "Hallo"))

    buffer.clear()

    XCTAssertTrue(buffer.items.isEmpty)
  }

  // MARK: - Source switch (pure)

  func testDisplayedUsesArchiveWhenEnabledAndCapsAtCap() {
    let archived = (0..<5).map { _ in dictation() }
    let session = [dictation(text: "session")]

    let shown = RecentDictationsBuffer.displayed(
      archiveEnabled: true, archived: archived, session: session)

    XCTAssertEqual(shown.map(\.id), archived.prefix(RecentDictationsBuffer.cap).map(\.id))
  }

  func testDisplayedUsesSessionWhenArchiveDisabled() {
    let archived = [dictation(text: "archiv")]
    let session = [dictation(text: "session")]

    let shown = RecentDictationsBuffer.displayed(
      archiveEnabled: false, archived: archived, session: session)

    XCTAssertEqual(shown.map(\.id), session.map(\.id))
  }

  // MARK: - Secure-field gate (pure) — a password-field run must never become a buffer item.

  func testBufferItemDropsSecureFieldRuns() {
    XCTAssertNil(RecentDictation.bufferItem(from: runRecord(), isSecureFieldTarget: true))
  }

  func testBufferItemMapsFieldsForNormalRuns() throws {
    let record = runRecord()

    let item = try XCTUnwrap(
      RecentDictation.bufferItem(from: record, isSecureFieldTarget: false))

    XCTAssertEqual(item.date, record.date)
    XCTAssertEqual(item.mode, record.mode)
    XCTAssertEqual(item.modeName, record.modeName)
    XCTAssertEqual(item.finalText, record.finalText)
  }

  private func runRecord() -> ArchiveRunRecord {
    ArchiveRunRecord(
      mode: .transcription,
      modeName: "Diktat",
      rawTranscript: "hallo welt",
      finalText: "Hallo Welt",
      backend: .local,
      durationSec: 2,
      date: Date(timeIntervalSince1970: 1_000)
    )
  }

  private func dictation(
    id: UUID? = nil,
    text: String = "Hallo Welt"
  ) -> RecentDictation {
    RecentDictation(
      id: id ?? UUID(),
      date: Date(timeIntervalSince1970: 1_000),
      mode: .transcription,
      modeName: "Diktat",
      finalText: text
    )
  }
}
