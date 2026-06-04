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

  /// A not-installed model must read "Nicht geladen — N MB" (never "Installiert"), and an
  /// installed one must read "Installiert".
  func testInstallStateLabelIsHonest() {
    let missing = LocalTranscriptionModel(
      id: "openai_whisper-small_216MB",
      url: URL(fileURLWithPath: "/tmp/nope"),
      isInstalled: false
    )
    XCTAssertEqual(missing.installStateLabel, "Nicht geladen — 216 MB")

    let present = LocalTranscriptionModel(
      id: "openai_whisper-small_216MB",
      url: URL(fileURLWithPath: "/tmp/yes"),
      isInstalled: true
    )
    XCTAssertEqual(present.installStateLabel, "Installiert")
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

  // MARK: - Ollama local LLM: installed-matching is normalization-aware

  /// Ollama reports fully-qualified tags ("gemma3:latest"); a curated bare name ("gemma3") must
  /// match it, while an explicit tag must match exactly. Nothing else may be reported as installed.
  func testOllamaInstalledMatchingNormalizesLatest() {
    let installed = ["gemma3:latest", "qwen3:8b"]
    XCTAssertTrue(OllamaService.isInstalled("gemma3", in: installed))
    XCTAssertTrue(OllamaService.isInstalled("gemma3:latest", in: installed))
    XCTAssertTrue(OllamaService.isInstalled("qwen3:8b", in: installed))
    // Curated names that are NOT pulled must report false.
    XCTAssertFalse(OllamaService.isInstalled("gemma3:12b", in: installed))
    XCTAssertFalse(OllamaService.isInstalled("qwen3", in: installed))
    XCTAssertFalse(OllamaService.isInstalled("llama3.2", in: installed))
  }

  func testOllamaNothingInstalledMatchesNothing() {
    XCTAssertFalse(OllamaService.isInstalled("gemma3", in: []))
    XCTAssertFalse(OllamaService.isInstalled("", in: ["gemma3:latest"]))
  }

  // MARK: - Ollama local LLM: picker rows flag pulled vs not-pulled honestly

  /// With zero models pulled, every curated suggestion must be flagged NOT installed —
  /// never presented as available. This is the user's exact observed-reality bug.
  func testOllamaPickerWithNothingPulledMarksAllCuratedNotInstalled() {
    let rows = OllamaService.pickerModels(installed: [])
    XCTAssertFalse(rows.isEmpty)
    XCTAssertTrue(rows.allSatisfy { !$0.isInstalled })
    XCTAssertTrue(rows.allSatisfy { $0.menuLabel.contains("nicht geladen") })
  }

  /// Actually-pulled models come first and are flagged installed; curated-but-missing follow.
  func testOllamaPickerListsInstalledFirstThenCurated() {
    let rows = OllamaService.pickerModels(installed: ["qwen3:8b"])
    let installedRow = try? XCTUnwrap(rows.first)
    XCTAssertEqual(installedRow?.name, "qwen3:8b")
    XCTAssertEqual(installedRow?.isInstalled, true)
    XCTAssertEqual(installedRow?.menuLabel, "qwen3:8b · geladen")

    // The pulled model must not also appear as a curated "not geladen" duplicate.
    XCTAssertEqual(rows.filter { $0.name == "qwen3:8b" }.count, 1)
    XCTAssertTrue(rows.contains { $0.name == "gemma3" && !$0.isInstalled })
  }

  /// The default for a fresh install is the empty "no model" sentinel — never a curated name.
  func testDefaultLocalLLMModelIsEmptySentinel() {
    XCTAssertEqual(OllamaService.defaultModelName, "")
    XCTAssertEqual(AppSettings().selectedLocalLLMModelName, "")
  }
}
