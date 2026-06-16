import XCTest

@testable import Rede

@MainActor
final class EmailSemanticMemoryStoreTests: XCTestCase {
  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("notabene-email-memory-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
  }

  func testAppendPersistsNewestFirstAndReloads() {
    let url = tempDir.appendingPathComponent("semantic-email-memory.json")
    let store = EmailSemanticMemoryStore(fileURL: url)
    store.append(makeRecord(finalText: "old", date: Date().addingTimeInterval(-10)))
    store.append(makeRecord(finalText: "new", date: Date()))

    let reloaded = EmailSemanticMemoryStore(fileURL: url)
    XCTAssertEqual(reloaded.records.map(\.finalText), ["new", "old"])
  }

  func testCapKeepsNewestRecords() {
    let store = EmailSemanticMemoryStore(fileURL: tempDir.appendingPathComponent("cap.json"))
    let total = EmailSemanticMemoryStore.maxEntries + 10
    for index in 0..<total {
      store.append(
        makeRecord(
          finalText: "mail-\(index)",
          date: Date().addingTimeInterval(Double(index - total))
        ))
    }
    XCTAssertEqual(store.records.count, EmailSemanticMemoryStore.maxEntries)
    XCTAssertEqual(store.records.first?.finalText, "mail-\(total - 1)")
  }

  func testRetentionDropsStaleRecordsOnAppend() {
    let store = EmailSemanticMemoryStore(fileURL: tempDir.appendingPathComponent("retention.json"))
    let stale = Date().addingTimeInterval(
      -Double(EmailSemanticMemoryStore.retentionDays + 2) * 86_400)
    store.append(makeRecord(finalText: "stale", date: stale))
    XCTAssertTrue(store.records.isEmpty)

    store.append(makeRecord(finalText: "fresh"))
    XCTAssertEqual(store.records.map(\.finalText), ["fresh"])
  }

  func testClearDeletesRecords() {
    let store = EmailSemanticMemoryStore(fileURL: tempDir.appendingPathComponent("clear.json"))
    store.append(makeRecord(finalText: "x"))
    store.clear()
    XCTAssertTrue(store.records.isEmpty)
  }

  private func makeRecord(finalText: String, date: Date = Date()) -> EmailSemanticMemoryRecord {
    EmailSemanticMemoryRecord(
      date: date,
      modeID: "textImprover",
      appBundleID: "com.example.mail",
      appName: "Mail",
      windowTitle: "Inbox",
      rawTranscript: "raw \(finalText)",
      finalText: finalText,
      embedding: [1, 0, 0],
      embeddingModel: "nomic-embed-text"
    )
  }
}

final class EmailMemoryRetrieverTests: XCTestCase {
  func testCosineRetrievalRanksMostSimilarRecords() throws {
    let records = [
      makeRecord(
        id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
        text: "A",
        embedding: [1, 0]),
      makeRecord(
        id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
        text: "B",
        embedding: [0, 1]),
      makeRecord(
        id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003")),
        text: "C",
        embedding: [0.8, 0.2]),
    ]

    let matches = EmailMemoryRetriever.retrieve(
      queryEmbedding: [1, 0],
      records: records,
      limit: 2,
      minScore: 0.1
    )

    XCTAssertEqual(matches.map(\.record.finalText), ["A", "C"])
    XCTAssertGreaterThan(matches[0].score, matches[1].score)
  }

  func testCosineReturnsZeroForMismatchedOrZeroVectors() {
    XCTAssertEqual(EmailMemoryRetriever.cosineSimilarity([1, 0], [0, 0]), 0)
    XCTAssertEqual(EmailMemoryRetriever.cosineSimilarity([1], [1, 0]), 0)
  }

  private func makeRecord(id: UUID, text: String, embedding: [Double]) -> EmailSemanticMemoryRecord
  {
    EmailSemanticMemoryRecord(
      id: id,
      date: Date(),
      modeID: "textImprover",
      appBundleID: nil,
      appName: nil,
      windowTitle: nil,
      rawTranscript: text,
      finalText: text,
      embedding: embedding,
      embeddingModel: "fixture"
    )
  }
}

final class LlamaCppEmbeddingDecodeTests: XCTestCase {
  func testDecodesOpenAIEmbeddingResponse() throws {
    let data = Data(#"{"data":[{"embedding":[0.1,0.2,0.3]}]}"#.utf8)
    XCTAssertEqual(try LlamaCppServerClient.decodeEmbedding(data), [0.1, 0.2, 0.3])
  }

  func testRejectsEmptyEmbedding() {
    let data = Data(#"{"data":[{"embedding":[]}]}"#.utf8)
    XCTAssertThrowsError(try LlamaCppServerClient.decodeEmbedding(data))
  }

  func testRejectsMissingData() {
    let data = Data(#"{"data":[]}"#.utf8)
    XCTAssertThrowsError(try LlamaCppServerClient.decodeEmbedding(data))
  }
}
