import XCTest

@testable import Blitztext

final class LocalLLMRuntimeTests: XCTestCase {
  func testRuntimeKindCodableRoundTrip() throws {
    let encoded = try JSONEncoder().encode(LocalLLMRuntimeKind.llamaCpp)
    let decoded = try JSONDecoder().decode(LocalLLMRuntimeKind.self, from: encoded)

    XCTAssertEqual(decoded, .llamaCpp)
    XCTAssertEqual(LocalLLMRuntimeKind.ollama.backendLabel, "Lokal (Ollama)")
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
}
