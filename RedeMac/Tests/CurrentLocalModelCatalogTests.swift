import XCTest

@testable import Rede

final class CurrentLocalModelCatalogTests: XCTestCase {
  private struct DownloadFixture {
    let id: String
    let repository: String
    let revision: String
    let fileName: String
    let sizeBytes: Int64
    let sha256: String
  }

  private let downloads: [DownloadFixture] = [
    DownloadFixture(
      id: "qwen3.5-4b-q4-k-m", repository: "unsloth/Qwen3.5-4B-GGUF",
      revision: "e87f176479d0855a907a41277aca2f8ee7a09523",
      fileName: "Qwen3.5-4B-Q4_K_M.gguf", sizeBytes: 2_740_937_888,
      sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"),
    DownloadFixture(
      id: "qwen3.5-9b-q4-k-m", repository: "unsloth/Qwen3.5-9B-GGUF",
      revision: "3885219b6810b007914f3a7950a8d1b469d598a5",
      fileName: "Qwen3.5-9B-Q4_K_M.gguf", sizeBytes: 5_680_522_464,
      sha256: "03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8"),
    DownloadFixture(
      id: "gemma-4-e2b-it-q4-0", repository: "ggml-org/gemma-4-E2B-it-GGUF",
      revision: "b4243c156154b6dca9324415f8c7ccc098b4aed1",
      fileName: "gemma-4-E2B-it-Q4_0.gguf", sizeBytes: 2_841_481_184,
      sha256: "8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52"),
    DownloadFixture(
      id: "gemma-4-e4b-it-q4-0", repository: "ggml-org/gemma-4-E4B-it-GGUF",
      revision: "b8093469224f83f5c38f691eb906c380e9e63114",
      fileName: "gemma-4-E4B-it-Q4_0.gguf", sizeBytes: 4_590_807_392,
      sha256: "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2")
  ]

  func testVerifiedCurrentModelsUseImmutableDownloadsAndPublisherMetadata() throws {
    for fixture in downloads {
      let model = try XCTUnwrap(LlamaCppModelCatalog.chatModel(for: fixture.id), fixture.id)
      XCTAssertEqual(model.repository, fixture.repository)
      XCTAssertEqual(model.minimumRuntimeBuild, "b9360")
      XCTAssertEqual(model.verification, .unverified)
      XCTAssertEqual(model.fileName, fixture.fileName)
      XCTAssertEqual(model.sizeBytes, fixture.sizeBytes)
      XCTAssertEqual(model.sha256, fixture.sha256)
      XCTAssertEqual(model.licenseName, "Apache-2.0")
      XCTAssertNotNil(model.licenseURL)
      XCTAssertEqual(model.downloadURL.scheme, "https")
      XCTAssertEqual(model.downloadURL.host, "huggingface.co")
      XCTAssertEqual(
        model.downloadURL.path,
        "/\(fixture.repository)/resolve/\(fixture.revision)/\(fixture.fileName)")
    }
  }

  func testLegacyCatalogSelectionsStillDecodeAndRoundTrip() throws {
    let legacyIDs = [
      "qwen3-1.7b-q4-k-m", "gemma-3-4b-it-q4-k-m", "qwen3-4b-q4-k-m",
      "qwen3-8b-q4-k-m", "gemma-3-12b-it-q4-k-m", "qwen3-14b-q4-k-m",
      "gemma-3-27b-it-q4-k-m", "qwen3-32b-q4-k-m"
    ]
    for id in legacyIDs {
      let json = """
        {"selectedLocalLLM":{"runtime":"llamaCpp","modelID":"\(id)"}}
        """
      let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
      XCTAssertEqual(decoded.selectedLocalLLM.modelID, id)
      XCTAssertTrue(decoded.selectedLocalLLM.isConfigured)
      let redecoded = try JSONDecoder().decode(
        AppSettings.self, from: JSONEncoder().encode(decoded))
      XCTAssertEqual(redecoded.selectedLocalLLM, decoded.selectedLocalLLM)
    }
  }

  func testCurrentModelsDoNotDisplaceExistingDefaultSelection() {
    XCTAssertEqual(LlamaCppModelCatalog.models.first?.id, "qwen3-1.7b-q4-k-m")
    XCTAssertFalse(AppSettings().selectedLocalLLM.isConfigured)
  }

  func testNewModelsRemainSelectableAfterSettingsRoundTrip() throws {
    for fixture in downloads {
      let settings = AppSettings(
        selectedLocalLLM: LocalLLMSelection(runtime: .llamaCpp, modelID: fixture.id))
      let decoded = try JSONDecoder().decode(
        AppSettings.self, from: JSONEncoder().encode(settings))
      XCTAssertEqual(decoded.selectedLocalLLM, settings.selectedLocalLLM)
    }
  }

  func testUnbenchmarkedModelsPreserveHardwareRecommendations() {
    let newIDs = Set(downloads.map(\.id))
    let legacyCatalog = LlamaCppModelCatalog.models.filter { !newIDs.contains($0.id) }
    for ram in [8.0, 16, 24, 32, 48, 64] {
      let capabilities = SystemCapabilities(
        totalRAMGB: ram, freeDiskGB: 200, chipName: "Test Chip", isAppleSilicon: true)
      XCTAssertEqual(
        capabilities.recommendedModel()?.id,
        capabilities.recommendedModel(from: legacyCatalog)?.id)
    }
  }

  func testOnlyExactLoadedArtifactHasLoadTestedVerification() {
    let sha = "90ce98129eb3e8cc57e62433d500c97c624b1e3af1fcc85dd3b55ad7e0313e9f"
    func fixture(fileName: String, hash: String, bytes: Int64 = 5_335_289_824) -> LlamaCppModelCatalog.Model {
      LlamaCppModelCatalog.Model(id: "custom-installed", displayName: "Fixture", fileName: fileName,
        downloadURL: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/fixture")!,
        sha256: hash, sizeBytes: bytes, estimatedRuntimeRAMGB: 8, parameterSize: "E4B",
        quantization: "Q4_K_M", licenseName: "Apache-2.0", licenseURL: nil, blurb: "", qualityRank: 0)
    }
    let known = fixture(fileName: "gemma-4-E4B-it-Q4_K_M.gguf", hash: sha)
    XCTAssertEqual(known.verification, .loadTested(build: "b9360", date: "2026-10-19"))
    XCTAssertEqual(known.minimumRuntimeBuild, "b9360")
    XCTAssertEqual(fixture(fileName: known.fileName, hash: "wrong").verification, .unverified)
    XCTAssertEqual(fixture(fileName: "gemma-4-E4B-it-Q4_0.gguf", hash: sha).verification, .unverified)
    XCTAssertEqual(fixture(fileName: known.fileName, hash: sha, bytes: 1).verification, .unverified)
  }

}
