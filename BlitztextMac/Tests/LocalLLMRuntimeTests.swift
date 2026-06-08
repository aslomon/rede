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

  func testLegacyOllamaModelNameMigratesToOllamaSelection() throws {
    let json = """
      {
        "selectedLocalLLMModelName": "gemma3:latest"
      }
      """

    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

    XCTAssertEqual(decoded.selectedLocalLLM.runtime, .ollama)
    XCTAssertEqual(decoded.selectedLocalLLM.modelID, "gemma3:latest")
    XCTAssertEqual(decoded.selectedLocalLLMModelName, "gemma3:latest")
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
