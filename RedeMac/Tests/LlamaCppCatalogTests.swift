import XCTest

@testable import Rede

/// Covers the local-LLM management logic that drives the "Lokale Modelle" page: the llama.cpp
/// catalog integrity, the hardware-based recommendation, GB formatting and fit/disk classification.
/// All pure logic — no live server required.
final class LlamaCppCatalogTests: XCTestCase {

  // MARK: - Catalog integrity

  func testChatCatalogIDsAreUnique() {
    let ids = LlamaCppModelCatalog.models.map(\.id)
    XCTAssertEqual(ids.count, Set(ids).count, "Catalog ids must be unique")
  }

  func testChatCatalogEntriesAreWellFormed() {
    for model in LlamaCppModelCatalog.models {
      XCTAssertFalse(model.id.isEmpty)
      XCTAssertTrue(model.fileName.hasSuffix(".gguf"), "\(model.id) needs a .gguf file name")
      XCTAssertGreaterThan(model.downloadGB, 0, "\(model.id) needs a positive download size")
      XCTAssertFalse(model.displayName.isEmpty)
      XCTAssertFalse(model.blurb.isEmpty)
      XCTAssertEqual(model.sha256.count, 64, "\(model.id) needs a full sha256")
      // Runtime RAM estimate must exceed the on-disk size (weights + overhead).
      XCTAssertGreaterThan(model.estimatedRuntimeRAMGB, model.downloadGB)
    }
  }

  func testEmbeddingCatalogIsSeparateFromChat() {
    let chatIDs = Set(LlamaCppModelCatalog.models.map(\.id))
    for embed in LlamaCppModelCatalog.embeddingModels {
      XCTAssertFalse(chatIDs.contains(embed.id), "Embedding model must not appear in the chat list")
    }
    XCTAssertFalse(LlamaCppModelCatalog.embeddingModels.isEmpty)
  }

  func testModelLookupSearchesChatAndEmbeddingButChatLookupDoesNot() {
    XCTAssertNotNil(LlamaCppModelCatalog.model(for: "qwen3-1.7b-q4-k-m"))
    XCTAssertNotNil(LlamaCppModelCatalog.model(for: LlamaCppModelCatalog.defaultEmbeddingModel.id))
    XCTAssertNil(
      LlamaCppModelCatalog.chatModel(for: LlamaCppModelCatalog.defaultEmbeddingModel.id),
      "chatModel(for:) must never return an embedding model")
  }

  // MARK: - Fit classification

  private func mac(ram: Double, disk: Double = 200, appleSilicon: Bool = true) -> SystemCapabilities
  {
    SystemCapabilities(
      totalRAMGB: ram, freeDiskGB: disk, chipName: "Test Chip", isAppleSilicon: appleSilicon)
  }

  func testFitThresholdsAppleSilicon() {
    let m = mac(ram: 48)  // comfortable ≤ 26.4, usable ≤ 33.6
    XCTAssertEqual(m.fit(forRuntimeRAMGB: 10), .comfortable)
    XCTAssertEqual(m.fit(forRuntimeRAMGB: 30), .tight)
    XCTAssertEqual(m.fit(forRuntimeRAMGB: 40), .tooLarge)
  }

  func testDiskFitsLeavesMargin() {
    let m = mac(ram: 16, disk: 20)
    XCTAssertTrue(m.diskFits(downloadGB: 17))  // 17 + 2 = 19 ≤ 20
    XCTAssertFalse(m.diskFits(downloadGB: 19))  // 19 + 2 = 21 > 20
  }

  // MARK: - Recommendation (over the llama.cpp catalog)

  func testRecommendationForLargeMacPicksHighestQualityComfortableModel() {
    let m = mac(ram: 64)
    let recommended = m.recommendedModel()
    let comfortable = LlamaCppModelCatalog.models.filter {
      m.diskFits(downloadGB: $0.downloadGB)
        && m.fit(forRuntimeRAMGB: $0.estimatedRuntimeRAMGB) == .comfortable
    }
    let best = comfortable.max(by: { $0.qualityRank < $1.qualityRank })
    XCTAssertEqual(recommended?.id, best?.id)
    XCTAssertNotNil(recommended)
  }

  func testRecommendationForSmallMacStaysWithinBudget() {
    let m = mac(ram: 8)
    guard let recommended = m.recommendedModel() else {
      return XCTFail("Expected a recommendation even on a small Mac")
    }
    XCTAssertNotEqual(
      m.fit(forRuntimeRAMGB: recommended.estimatedRuntimeRAMGB), .tooLarge,
      "Recommendation must never exceed the machine's usable RAM")
  }

  func testRecommendationFallsBackToSmallestWhenDiskTiny() {
    let recommended = mac(ram: 64, disk: 2).recommendedModel()
    XCTAssertEqual(
      recommended?.id, LlamaCppModelCatalog.models.min { $0.downloadGB < $1.downloadGB }?.id)
  }

  func testRecommendationReasonIsHonestGerman() {
    let model = LlamaCppModelCatalog.models[0]
    XCTAssertTrue(mac(ram: 64).recommendationReason(for: model).contains("RAM"))
  }

  // MARK: - GB formatting

  func testFormatGB() {
    XCTAssertEqual(SystemCapabilities.formatGB(48), "48 GB")
    XCTAssertEqual(SystemCapabilities.formatGB(17), "17 GB")
    XCTAssertEqual(SystemCapabilities.formatGB(8.1), "8,1 GB")
    XCTAssertEqual(SystemCapabilities.formatGB(0.8), "0,8 GB")
  }

  // MARK: - Custom models (manual URL)

  func testCustomModelFromValidGGUFURL() {
    let model = LlamaCppModelCatalog.customModel(
      fromURLString:
        "https://huggingface.co/foo/bar/resolve/main/My-Model.Q4_K_M.gguf?download=true")
    XCTAssertNotNil(model)
    XCTAssertEqual(model?.fileName, "My-Model.Q4_K_M.gguf")
    XCTAssertEqual(model?.id, "custom-my-model-q4-k-m")
    XCTAssertEqual(model?.sha256, "", "Custom models have no pinned checksum")
  }

  func testCustomModelRejectsNonGGUFAndBadInput() {
    XCTAssertNil(LlamaCppModelCatalog.customModel(fromURLString: "https://example.com/model.bin"))
    XCTAssertNil(LlamaCppModelCatalog.customModel(fromURLString: "ftp://example.com/model.gguf"))
    XCTAssertNil(LlamaCppModelCatalog.customModel(fromURLString: "not a url"))
    XCTAssertNil(LlamaCppModelCatalog.customModel(fromURLString: ""))
  }

  func testInstalledModelUsesCatalogEntryWhenKnown() {
    let manifest = LlamaCppModelStore.VerifiedManifest(
      modelID: "qwen3-1.7b-q4-k-m", fileName: "Qwen3-1.7B-Q4_K_M.gguf", sha256: "x", sizeBytes: 1)
    XCTAssertEqual(
      LlamaCppModelCatalog.installedModel(from: manifest).displayName, "Qwen3 · 1.7B · Q4_K_M")
  }

  func testInstalledModelDerivesDescriptorForCustom() {
    let manifest = LlamaCppModelStore.VerifiedManifest(
      modelID: "custom-foo", fileName: "Foo.gguf", sha256: "abc", sizeBytes: 2_000_000_000,
      displayName: "Foo", parameterSize: "7B", quantization: "Q4_K_M",
      downloadURL: "https://example.com/Foo.gguf")
    let model = LlamaCppModelCatalog.installedModel(from: manifest)
    XCTAssertEqual(model.id, "custom-foo")
    XCTAssertEqual(model.displayName, "Foo")
    XCTAssertEqual(model.parameterSize, "7B")
  }
}
