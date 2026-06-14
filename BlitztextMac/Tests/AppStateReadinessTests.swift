import XCTest

@testable import Blitztext

@MainActor
final class AppStateReadinessTests: XCTestCase {
  func testOnlineProcessingDoesNotAskForLocalModelsOnMainPage() {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var settings = AppSettings()
    settings.secureLocalModeEnabled = false
    let state = AppState(
      appSettings: settings,
      localModelManager: LocalModelManager(store: LlamaCppModelStore(rootDirectory: root)),
      prewarmEnginesAtLaunch: false
    )

    let issueIDs = Set(state.mainPageReadinessIssues.map(\.id))

    XCTAssertFalse(issueIDs.contains("local-whisper"))
    XCTAssertFalse(issueIDs.contains("local-llm"))
  }

  func testLocalProcessingShowsMissingLocalLLMForRewriteModes() {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var settings = AppSettings()
    settings.secureLocalModeEnabled = true
    let state = AppState(
      appSettings: settings,
      localModelManager: LocalModelManager(store: LlamaCppModelStore(rootDirectory: root)),
      prewarmEnginesAtLaunch: false
    )

    let issueIDs = Set(state.mainPageReadinessIssues.map(\.id))

    XCTAssertTrue(issueIDs.contains("local-llm"))
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}
