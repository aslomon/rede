import XCTest

@testable import Rede

final class LocalLLMRuntimeTests: XCTestCase {
  func testRuntimeKindCodableRoundTrip() throws {
    let encoded = try JSONEncoder().encode(LocalLLMRuntimeKind.llamaCpp)
    let decoded = try JSONDecoder().decode(LocalLLMRuntimeKind.self, from: encoded)

    XCTAssertEqual(decoded, .llamaCpp)
    XCTAssertEqual(LocalLLMRuntimeKind.llamaCpp.backendLabel, "Lokal (llama.cpp)")
  }

  func testSelectionTrimsModelIDAndPreservesRuntime() {
    let selection = LocalLLMSelection(runtime: .llamaCpp, modelID: "  qwen3-1.7b-q4-k-m  ")

    XCTAssertEqual(selection.modelID, "qwen3-1.7b-q4-k-m")
    XCTAssertEqual(selection.runtime, .llamaCpp)
    XCTAssertTrue(selection.isConfigured)
  }

  func testDefaultSettingsPreferLlamaCppWithoutPretendingModelIsInstalled() {
    let settings = AppSettings()

    XCTAssertEqual(settings.selectedLocalLLM.runtime, .llamaCpp)
    XCTAssertEqual(settings.selectedLocalLLM.modelID, "")
    XCTAssertFalse(settings.selectedLocalLLM.isConfigured)
    XCTAssertEqual(settings.selectedLocalLLMModelName, "")
  }

  func testLegacyOllamaModelNameIsDroppedAfterOllamaRemoval() throws {
    // Ollama was removed: a legacy single-string model name (always an Ollama tag) can't run on
    // llama.cpp, so the selection must come back unconfigured rather than silently failing.
    let json = """
      {
        "selectedLocalLLMModelName": "gemma3:latest"
      }
      """

    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

    XCTAssertFalse(decoded.selectedLocalLLM.isConfigured)
    XCTAssertEqual(decoded.selectedLocalLLM.modelID, "")
    XCTAssertEqual(decoded.selectedLocalLLMModelName, "gemma3:latest")
  }

  func testExplicitOllamaSelectionIsDroppedAfterOllamaRemoval() throws {
    // An explicitly-stored Ollama selection is unknown to the llama.cpp catalog and is discarded.
    let json = """
      {
        "selectedLocalLLM": {
          "runtime": "ollama",
          "modelID": "gemma3:latest"
        }
      }
      """

    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

    XCTAssertFalse(decoded.selectedLocalLLM.isConfigured)
    XCTAssertEqual(decoded.selectedLocalLLM.modelID, "")
  }

  func testExplicitSelectionWinsOverLegacyModelName() throws {
    let json = """
      {
        "selectedLocalLLM": {
          "runtime": "llamaCpp",
          "modelID": "qwen3-1.7b-q4-k-m"
        },
        "selectedLocalLLMModelName": "gemma3:latest"
      }
      """

    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

    XCTAssertEqual(decoded.selectedLocalLLM.runtime, .llamaCpp)
    XCTAssertEqual(decoded.selectedLocalLLM.modelID, "qwen3-1.7b-q4-k-m")
    XCTAssertEqual(decoded.selectedLocalLLMModelName, "gemma3:latest")
  }

  func testLegacyOllamaEmbeddingModelMigratesToLlamaCppDefault() throws {
    // The old Ollama embedding tag is not a llama.cpp embedding model — decode must fall back to
    // the default GGUF embedding model so semantic e-mail memory keeps working without Ollama.
    let json = """
      {
        "selectedEmbeddingModelName": "nomic-embed-text"
      }
      """

    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

    XCTAssertEqual(decoded.selectedEmbeddingModelName, LlamaCppEmbeddingProvider.defaultModelID)
    XCTAssertTrue(
      LlamaCppModelCatalog.embeddingModels.contains { $0.id == decoded.selectedEmbeddingModelName })
  }

  @MainActor
  func testLaunchAdoptsInstalledLlamaCppModelBeforePrewarm() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LlamaCppModelStore(rootDirectory: root)
    let model = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    try store.ensureRootExists()
    let finalURL = try store.finalURL(for: model)
    try Data("model".utf8).write(to: finalURL)
    try store.writeVerifiedManifest(for: model, fileURL: finalURL)

    let manager = LocalModelManager(store: store)
    let state = AppState(
      appSettings: AppSettings(),
      localModelManager: manager,
      prewarmEnginesAtLaunch: false
    )

    XCTAssertEqual(
      state.appSettings.selectedLocalLLM,
      LocalLLMSelection(runtime: .llamaCpp, modelID: model.id)
    )
    XCTAssertFalse(state.localRewritePreparing)
  }

  @MainActor
  func testLaunchReplacesStaleLlamaCppSelectionWithInstalledModel() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LlamaCppModelStore(rootDirectory: root)
    let model = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    try store.ensureRootExists()
    let finalURL = try store.finalURL(for: model)
    try Data("model".utf8).write(to: finalURL)
    try store.writeVerifiedManifest(for: model, fileURL: finalURL)

    var settings = AppSettings()
    settings.selectedLocalLLM = LocalLLMSelection(runtime: .llamaCpp, modelID: "missing-model")
    let manager = LocalModelManager(store: store)
    let state = AppState(
      appSettings: settings,
      localModelManager: manager,
      prewarmEnginesAtLaunch: false
    )

    XCTAssertEqual(
      state.appSettings.selectedLocalLLM,
      LocalLLMSelection(runtime: .llamaCpp, modelID: model.id)
    )
  }

  @MainActor
  func testOnlineProcessingForcesOpenAIRewriteEvenIfModeStoredLocal() {
    var settings = AppSettings()
    settings.secureLocalModeEnabled = false
    let state = AppState(appSettings: settings, prewarmEnginesAtLaunch: false)

    var mode = ModeConfig.default(for: .textImprover)
    mode.rewrite.rewriteBackend = .local

    XCTAssertEqual(state.resolvedRewriteBackend(for: mode), .openai)
  }

  @MainActor
  func testLocalProcessingForcesLocalRewriteEvenIfModeStoredOpenAI() {
    var settings = AppSettings()
    settings.secureLocalModeEnabled = true
    let state = AppState(appSettings: settings, prewarmEnginesAtLaunch: false)

    var mode = ModeConfig.default(for: .textImprover)
    mode.rewrite.rewriteBackend = .openai

    XCTAssertEqual(state.resolvedRewriteBackend(for: mode), .local)
  }

  @MainActor
  func testOnlineLaunchDoesNotPrewarmInstalledLocalRewriteModel() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LlamaCppModelStore(rootDirectory: root)
    let model = try XCTUnwrap(LlamaCppModelCatalog.models.first)
    try store.ensureRootExists()
    let finalURL = try store.finalURL(for: model)
    try Data("model".utf8).write(to: finalURL)
    try store.writeVerifiedManifest(for: model, fileURL: finalURL)

    var settings = AppSettings()
    settings.secureLocalModeEnabled = false
    settings.selectedLocalLLM = LocalLLMSelection(runtime: .llamaCpp, modelID: model.id)
    let manager = LocalModelManager(store: store)
    let state = AppState(
      appSettings: settings,
      localModelManager: manager,
      prewarmEnginesAtLaunch: true
    )

    XCTAssertEqual(state.resolvedRewriteBackend(for: .textImprover), .openai)
    XCTAssertFalse(state.localRewritePreparing)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}
