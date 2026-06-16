import XCTest

@testable import Rede

/// Pure mapping/parsing logic for the live Hugging Face catalog — no network.
final class HuggingFaceModelServiceTests: XCTestCase {
  func testParamCountParsing() {
    XCTAssertEqual(HuggingFaceModelService.paramCount(from: "Qwen3-14B-Q4_K_M.gguf"), 14)
    XCTAssertEqual(HuggingFaceModelService.paramCount(from: "Qwen3-0.6B-GGUF"), 0.6)
    XCTAssertEqual(HuggingFaceModelService.paramCount(from: "gemma-3-27b-it"), 27)
    XCTAssertNil(HuggingFaceModelService.paramCount(from: "no-params-here"))
  }

  func testMakeModelDerivesFieldsFromRepo() {
    let model = HuggingFaceModelService.makeModel(
      repo: "ggml-org/Qwen3-14B-GGUF", fileName: "Qwen3-14B-Q4_K_M.gguf",
      sha256: "abc", sizeBytes: 9_000_000_000)
    XCTAssertEqual(model.id, "hf-ggml-org-qwen3-14b-gguf")
    XCTAssertEqual(model.parameterSize, "14B")
    XCTAssertEqual(model.sha256, "abc")
    XCTAssertEqual(model.quantization, "Q4_K_M")
    XCTAssertTrue(model.downloadURL.absoluteString.contains("Qwen3-14B-Q4_K_M.gguf"))
    XCTAssertGreaterThan(model.qualityRank, 0)
  }

  func testDedupDropsCuratedFileNames() {
    let curated = HuggingFaceModelService.makeModel(
      repo: "ggml-org/Qwen3-1.7B-GGUF", fileName: "Qwen3-1.7B-Q4_K_M.gguf",
      sha256: "x", sizeBytes: 1_280_000_000)
    let novel = HuggingFaceModelService.makeModel(
      repo: "ggml-org/gemma-4-12B-it-GGUF", fileName: "gemma-4-12B-it-Q4_K_M.gguf",
      sha256: "y", sizeBytes: 7_000_000_000)
    let result = HuggingFaceModelService.deduped([curated, novel])
    XCTAssertEqual(result.map(\.fileName), ["gemma-4-12B-it-Q4_K_M.gguf"])
  }

  func testExcludedFragmentsCoverKnownJunk() {
    let junk = [
      "ggml-org/embeddinggemma-300M-GGUF", "ggml-org/SmolVLM-500M-Instruct-GGUF",
      "ggml-org/test-model-stories260K", "ggml-org/models-moved",
    ]
    for repo in junk {
      XCTAssertTrue(
        HuggingFaceModelService.excludedFragments.contains { repo.lowercased().contains($0) },
        "\(repo) should be excluded")
    }
  }
}
