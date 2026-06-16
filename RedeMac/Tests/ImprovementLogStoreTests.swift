import XCTest

@testable import Rede

/// MEM-2 `ImprovementLogStore` is the most PII-heavy store in the app (it holds the actual
/// before/after TEXT of a correction), so its bounds matter: newest-first append, count cap, and —
/// the focus of these tests — the 30-day age retention that guarantees old corrections expire even
/// if the user never opens "Verlauf löschen". A fresh temp file backs every store (no shared state).
final class ImprovementLogStoreTests: XCTestCase {

  // MARK: - Append / cap / clear

  @MainActor
  func testAppendInsertsNewestFirst() {
    let store = makeStore()
    store.append(makeObservation(inserted: "a"))
    store.append(makeObservation(inserted: "b"))
    XCTAssertEqual(store.observations.count, 2)
    XCTAssertEqual(store.observations.first?.inserted, "b")
  }

  @MainActor
  func testCapKeepsMostRecentEntries() {
    let store = makeStore()
    let total = ImprovementLogStore.maxEntries + 25
    for index in 0..<total {
      store.append(makeObservation(inserted: "n\(index)"))
    }
    XCTAssertEqual(store.observations.count, ImprovementLogStore.maxEntries)
    XCTAssertEqual(store.observations.first?.inserted, "n\(total - 1)")
  }

  @MainActor
  func testClearEmptiesTheStore() {
    let store = makeStore()
    store.append(makeObservation(inserted: "x"))
    store.clear()
    XCTAssertTrue(store.observations.isEmpty)
  }

  // MARK: - Retention (age-based pruning)

  @MainActor
  func testAppendDropsObservationOlderThanRetention() {
    let store = makeStore()
    let stale = Date().addingTimeInterval(-Double(ImprovementLogStore.retentionDays + 2) * 86_400)
    store.append(makeObservation(inserted: "old", date: stale))
    // A correction older than the (shorter, text-bearing) retention window is pruned on mutation.
    XCTAssertTrue(store.observations.isEmpty)
    store.append(makeObservation(inserted: "new"))
    XCTAssertEqual(store.observations.count, 1)
    XCTAssertEqual(store.observations.first?.inserted, "new")
  }

  @MainActor
  func testPruneExpiredKeepsFreshEntriesAndIsSafe() {
    let store = makeStore()
    store.append(makeObservation(inserted: "fresh"))
    store.pruneExpired()  // shares prune() with load; must not drop valid data
    XCTAssertEqual(store.observations.count, 1)
    XCTAssertEqual(store.observations.first?.inserted, "fresh")
  }

  @MainActor
  func testLoadPrunesStaleObservationsFromDisk() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("improvelog-retention-\(UUID().uuidString).json")
    let fresh = makeObservation(inserted: "keep")
    let stale = makeObservation(
      inserted: "drop",
      date: Date().addingTimeInterval(-Double(ImprovementLogStore.retentionDays + 5) * 86_400))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([fresh, stale]).write(to: url)

    let store = ImprovementLogStore(fileURL: url)
    XCTAssertEqual(store.observations.count, 1)
    XCTAssertEqual(store.observations.first?.inserted, "keep")
  }

  // MARK: - Helpers

  @MainActor
  private func makeStore() -> ImprovementLogStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("improvelog-\(UUID().uuidString).json")
    return ImprovementLogStore(fileURL: url)
  }

  private func makeObservation(inserted: String, date: Date = Date()) -> ImprovementObservation {
    ImprovementObservation(
      date: date,
      appBundleID: "com.example.app",
      appName: "Example",
      mode: "transcription",
      inserted: inserted,
      finalText: inserted,
      changed: false
    )
  }
}
