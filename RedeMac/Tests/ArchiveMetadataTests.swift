import XCTest

@testable import Rede

final class ArchiveMetadataTests: XCTestCase {
  func testArchiveEntryPreservesDynamicModeMetadataFromRunRecord() {
    let record = ArchiveRunRecord(
      mode: .textImprover,
      modeID: "email-client-a",
      modeName: "E-Mail Kunde A",
      rawTranscript: "raw",
      finalText: "final",
      backend: .remote,
      durationSec: 1.5,
      date: Date(timeIntervalSince1970: 1_000)
    )

    let entry = ArchiveEntry(record: record)

    XCTAssertEqual(entry.mode, .textImprover)
    XCTAssertEqual(entry.modeID, "email-client-a")
    XCTAssertEqual(entry.modeName, "E-Mail Kunde A")
    XCTAssertEqual(entry.rawTranscript, "raw")
    XCTAssertEqual(entry.finalText, "final")
  }

  func testLegacyArchiveEntryWithoutModeMetadataStillDecodes() throws {
    let json = """
      {
        "backend": "remote",
        "date": "2026-06-08T10:00:00Z",
        "durationSec": 2,
        "finalText": "Hallo",
        "id": "11111111-1111-1111-1111-111111111111",
        "mode": "textImprover",
        "rawTranscript": "Hallo"
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let entry = try decoder.decode(ArchiveEntry.self, from: Data(json.utf8))

    XCTAssertEqual(entry.mode, .textImprover)
    XCTAssertNil(entry.modeID)
    XCTAssertNil(entry.modeName)
    XCTAssertEqual(entry.finalText, "Hallo")
  }

  func testArchiveRunRecordCanBeEnrichedWithoutChangingTextPayload() {
    let record = ArchiveRunRecord(
      mode: .dampfAblassen,
      rawTranscript: "raw",
      finalText: "final",
      backend: .local,
      durationSec: 3
    )

    let enriched = record.withModeMetadata(id: "prompt-client", name: "Prompt Kunde")

    XCTAssertEqual(enriched.mode, .dampfAblassen)
    XCTAssertEqual(enriched.modeID, "prompt-client")
    XCTAssertEqual(enriched.modeName, "Prompt Kunde")
    XCTAssertEqual(enriched.rawTranscript, record.rawTranscript)
    XCTAssertEqual(enriched.finalText, record.finalText)
    XCTAssertEqual(enriched.backend, record.backend)
  }
}
