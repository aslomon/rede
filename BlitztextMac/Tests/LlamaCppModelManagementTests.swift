import XCTest

@testable import Blitztext

final class LlamaCppModelManagementTests: XCTestCase {
  func testCatalogEntriesAreSafeAndComplete() {
    let ids = LlamaCppModelCatalog.models.map(\.id)

    XCTAssertEqual(ids.count, Set(ids).count)
    XCTAssertFalse(LlamaCppModelCatalog.models.isEmpty)

    for model in LlamaCppModelCatalog.models {
      XCTAssertFalse(model.id.isEmpty)
      XCTAssertFalse(model.displayName.isEmpty)
      XCTAssertFalse(model.fileName.isEmpty)
      XCTAssertTrue(model.fileName.hasSuffix(".gguf"))
      XCTAssertTrue(model.downloadURL.absoluteString.hasPrefix("https://"))
      XCTAssertFalse(model.sha256.isEmpty)
      XCTAssertGreaterThan(model.sizeBytes, 0)
      XCTAssertGreaterThan(model.estimatedRuntimeRAMGB, 0)
      XCTAssertFalse(model.licenseName.isEmpty)
      XCTAssertFalse(model.quantization.isEmpty)
    }
  }

  func testModelStoreRejectsPathTraversalFileNames() throws {
    let root = temporaryDirectory()
    let store = LlamaCppModelStore(rootDirectory: root)
    let malicious = LlamaCppModelCatalog.Model(
      id: "bad",
      displayName: "Bad",
      fileName: "../bad.gguf",
      downloadURL: try XCTUnwrap(URL(string: "https://example.com/bad.gguf")),
      sha256: "abc",
      sizeBytes: 1,
      estimatedRuntimeRAMGB: 1,
      parameterSize: "1B",
      quantization: "Q4_K_M",
      licenseName: "Test",
      licenseURL: nil,
      blurb: "Bad path"
    )

    XCTAssertThrowsError(try store.finalURL(for: malicious))
  }

  func testPartialFilesNeverCountAsInstalled() throws {
    let root = temporaryDirectory()
    let store = LlamaCppModelStore(rootDirectory: root)
    let model = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    try store.ensureRootExists()
    let partial = try store.partialURL(for: model)
    try Data("partial".utf8).write(to: partial)

    XCTAssertFalse(store.isInstalled(model))
  }

  func testFinalFileCountsAsInstalled() throws {
    let root = temporaryDirectory()
    let store = LlamaCppModelStore(rootDirectory: root)
    let model = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    try store.ensureRootExists()
    let finalURL = try store.finalURL(for: model)
    try Data("model".utf8).write(to: finalURL)
    try store.writeVerifiedManifest(for: model, fileURL: finalURL)

    XCTAssertTrue(store.isInstalled(model))
  }

  func testFinalFileWithoutManifestDoesNotCountAsInstalled() throws {
    let root = temporaryDirectory()
    let store = LlamaCppModelStore(rootDirectory: root)
    let model = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    try store.ensureRootExists()
    let finalURL = try store.finalURL(for: model)
    try Data("model".utf8).write(to: finalURL)

    XCTAssertFalse(store.isInstalled(model))
  }

  func testSha256UsesExpectedHexDigest() throws {
    let root = temporaryDirectory()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileURL = root.appendingPathComponent("fixture.txt")
    try Data("blitztext".utf8).write(to: fileURL)

    XCTAssertEqual(
      try LlamaCppDownloadService.sha256Hex(for: fileURL),
      "c35b6d671fd783ce732914fae87feca0d63a24187e9c6cd74a52a6a45dcfe3f1"
    )
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}
