import XCTest

@testable import Rede

final class CurrentModelMetadataTests: XCTestCase {
  func testLegacyCatalogOrderAndAppendOnlyCurrentModels() {
    let legacy = [
      "qwen3-1.7b-q4-k-m", "gemma-3-4b-it-q4-k-m", "qwen3-4b-q4-k-m", "qwen3-8b-q4-k-m",
      "gemma-3-12b-it-q4-k-m", "qwen3-14b-q4-k-m", "gemma-3-27b-it-q4-k-m", "qwen3-32b-q4-k-m"
    ]
    XCTAssertEqual(Array(LlamaCppModelCatalog.models.prefix(legacy.count).map(\.id)), legacy)
    XCTAssertEqual(Array(LlamaCppModelCatalog.models.dropFirst(legacy.count)), LlamaCppModelCatalog.currentModels)
  }

  func testExactVerifiedInstalledManifestRetainsLoadTestedMetadata() {
    let manifest = LlamaCppModelStore.VerifiedManifest(modelID: "hf-ggml-org-gemma-4-e4b-it-gguf",
      fileName: "gemma-4-E4B-it-Q4_K_M.gguf",
      sha256: "90ce98129eb3e8cc57e62433d500c97c624b1e3af1fcc85dd3b55ad7e0313e9f",
      sizeBytes: 5_335_289_824, displayName: "Installed Gemma", parameterSize: "E4B",
      quantization: "Q4_K_M", downloadURL: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/model")
    let model = LlamaCppModelCatalog.installedModel(from: manifest)
    XCTAssertEqual(model.id, manifest.modelID)
    XCTAssertEqual(model.sha256, manifest.sha256)
    XCTAssertEqual(model.verification, .loadTested(build: "b9360", date: "2026-10-19"))
    XCTAssertEqual(model.minimumRuntimeBuild, "b9360")
    XCTAssertEqual(model.repository, "ggml-org/gemma-4-E4B-it-GGUF")
    for current in LlamaCppModelCatalog.currentModels { XCTAssertEqual(current.verification, .unverified) }
  }
}
