import XCTest

@testable import Blitztext

/// Guards the "honest local-model state" contract for BOTH local concepts the UI exposes:
///   1. WhisperKit transcription models (speech -> text), state derived from disk.
///   2. Ollama local LLM rewrite models, state derived from `GET /api/tags`.
/// A picker must NEVER label a model "installed/geladen" unless it is truly on disk / pulled.
final class LocalModelStateTests: XCTestCase {

  // MARK: - WhisperKit transcription model: size + state labels

  func testSizeLabelParsedFromModelNameSuffix() {
    XCTAssertEqual(LocalTranscriptionModel.sizeLabel(for: "openai_whisper-small_216MB"), "216 MB")
    XCTAssertEqual(
      LocalTranscriptionModel.sizeLabel(for: "openai_whisper-large-v3-v20240930_626MB"), "626 MB")
    XCTAssertEqual(
      LocalTranscriptionModel.sizeLabel(for: "openai_whisper-large-v3-v20240930_turbo_632MB"),
      "632 MB")
  }

  func testSizeLabelNilWhenNoSizeHint() {
    XCTAssertNil(LocalTranscriptionModel.sizeLabel(for: "some-model-without-size"))
  }

  /// A not-installed model must read "nicht geladen — N MB" (never "geladen"), and an
  /// installed one must read "geladen" (rede voice: lowercase UI copy).
  func testInstallStateLabelIsHonest() {
    let missing = LocalTranscriptionModel(
      id: "openai_whisper-small_216MB",
      url: URL(fileURLWithPath: "/tmp/nope"),
      isInstalled: false
    )
    XCTAssertEqual(missing.installStateLabel, "nicht geladen — 216 MB")

    let present = LocalTranscriptionModel(
      id: "openai_whisper-small_216MB",
      url: URL(fileURLWithPath: "/tmp/yes"),
      isInstalled: true
    )
    XCTAssertEqual(present.installStateLabel, "geladen")
  }

  // MARK: - WhisperKit transcription model: disk-truth `isUsableModel`

  /// A directory with the three `.mlmodelc` packages but NO `config.json` (the classic
  /// interrupted-download state) must NOT count as installed. This is the core accuracy fix:
  /// before, such a directory falsely reported "Installiert" and then crashed at load.
  func testModelMissingConfigJsonIsNotUsable() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    for package in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
      try fileManager.createDirectory(
        at: root.appendingPathComponent(package), withIntermediateDirectories: true)
    }

    // config.json intentionally absent -> not usable.
    XCTAssertFalse(LocalTranscriptionService.isUsableModel(at: root))

    // Add config.json -> now usable.
    try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
    XCTAssertTrue(LocalTranscriptionService.isUsableModel(at: root))
  }

  func testModelMissingMlmodelcIsNotUsable() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
    // Only one of the three required packages present.
    try fileManager.createDirectory(
      at: root.appendingPathComponent("AudioEncoder.mlmodelc"), withIntermediateDirectories: true)

    XCTAssertFalse(LocalTranscriptionService.isUsableModel(at: root))
  }

  // MARK: - WhisperKit transcription model: selection after delete

  /// Deleting a model the user was NOT using must leave the active selection untouched.
  func testSelectionAfterDeletingKeepsUnaffectedSelection() {
    let result = LocalTranscriptionService.selectionAfterDeleting(
      deletedModelName: LocalTranscriptionService.fastModelName,
      currentSelection: LocalTranscriptionService.recommendedFastModelName,
      remainingInstalledIDs: [LocalTranscriptionService.recommendedFastModelName]
    )
    XCTAssertEqual(result, LocalTranscriptionService.recommendedFastModelName)
  }

  /// Deleting the active model falls back to the recommended fast model when it is still on disk.
  func testSelectionAfterDeletingFallsBackToRecommendedFast() {
    let result = LocalTranscriptionService.selectionAfterDeleting(
      deletedModelName: LocalTranscriptionService.defaultModelName,
      currentSelection: LocalTranscriptionService.defaultModelName,
      remainingInstalledIDs: [
        LocalTranscriptionService.recommendedFastModelName,
        LocalTranscriptionService.fastModelName,
      ]
    )
    XCTAssertEqual(result, LocalTranscriptionService.recommendedFastModelName)
  }

  /// When the recommended fast model is gone too, fall back to whatever installed model remains.
  func testSelectionAfterDeletingFallsBackToFirstRemaining() {
    let result = LocalTranscriptionService.selectionAfterDeleting(
      deletedModelName: LocalTranscriptionService.recommendedFastModelName,
      currentSelection: LocalTranscriptionService.recommendedFastModelName,
      remainingInstalledIDs: [LocalTranscriptionService.fastModelName]
    )
    XCTAssertEqual(result, LocalTranscriptionService.fastModelName)
  }

  /// Deleting the last installed model leaves the recommended name as a safe (not-installed) default
  /// rather than an empty or stale selection.
  func testSelectionAfterDeletingLastModelDefaultsToRecommendedName() {
    let result = LocalTranscriptionService.selectionAfterDeleting(
      deletedModelName: LocalTranscriptionService.fastModelName,
      currentSelection: LocalTranscriptionService.fastModelName,
      remainingInstalledIDs: []
    )
    XCTAssertEqual(result, LocalTranscriptionService.recommendedFastModelName)
  }

  /// The default for a fresh install is the empty "no model" sentinel — never a curated name.
  func testDefaultLocalLLMModelIsEmptySentinel() {
    XCTAssertEqual(AppSettings().selectedLocalLLMModelName, "")
  }
}
