import XCTest

@testable import Rede

/// Guards for the new German copy and the model badges: no perfection claims, no retention
/// promises, the brand's lowercase voice, and honest badges.
final class RefreshCopyTests: XCTestCase {
  private let forbidden = ["perfekt", "garantiert", "immer richtig", "nicht gespeichert"]

  private var allEnumCopy: [String] {
    let notes: [PurposeRoutingNote] =
      [.detected(.email), .detected(.aiPrompt), .noSpecialPurpose]
      + [NeutralReason.timeout, .lowConfidence, .tooShort, .transport].map { .fellBack($0) }
    let live: [LiveTranscriptModel.Note] =
      [.connecting, .listening, .finishing, .fallsBackToRecording]
    let blocks: [NetworkFeatureBlock] = [.secureLocal, .localRewrite, .noAPIKey, .noMicrophone]
    let failures: [UpdateService.Failure] = [.network, .invalidSignature, .cannotInstall, .other]
    return notes.map(\.copy) + live.map(\.copy) + blocks.map(\.copy) + failures.map(\.message)
  }

  func testNoCopyPromisesPerfectResultsOrStorageGuarantees() {
    for text in allEnumCopy {
      for phrase in forbidden {
        XCTAssertFalse(text.lowercased().contains(phrase), "\(phrase) in: \(text)")
      }
    }
  }

  func testStatusCopyFollowsTheLowercaseVoice() {
    for text in allEnumCopy {
      XCTAssertTrue(text.first?.isLowercase ?? false, "copy should start lowercase: \(text)")
    }
  }

  func testUnsureAutomatikSaysEverythingRanAsUsual() {
    let unsure: [NeutralReason] = [.timeout, .lowConfidence, .lowMargin, .refusal, .transport]
    for reason in unsure {
      XCTAssertTrue(
        PurposeRoutingNote.fellBack(reason).copy.contains("wie gewohnt"), "\(reason)")
    }
    XCTAssertTrue(PurposeRoutingNote.noSpecialPurpose.copy.contains("wie gewohnt"))
  }

  func testSecureLocalCopyNamesTheReason() {
    XCTAssertTrue(NetworkFeatureBlock.secureLocal.copy.contains("lokalmodus"))
  }

  func testStoppedLiveIsNotPresentedAsAnError() {
    let copy = LiveTranscriptModel.Note.fallsBackToRecording.copy
    XCTAssertFalse(copy.contains("fehler"))
    XCTAssertTrue(copy.contains("transkribiere"))
  }

  // MARK: - Source-level copy guard

  func testNewSettingsViewsContainNoRetentionOrPerfectionClaims() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Features/Settings")
    for name in ["OnlineExtrasSection", "UpdatesSettingsSection", "RecommendedModelOfferBanner"] {
      let source = try String(
        contentsOf: root.appendingPathComponent("\(name).swift"), encoding: .utf8
      ).lowercased()
      for phrase in forbidden {
        XCTAssertFalse(source.contains(phrase), "\(name) contains \(phrase)")
      }
    }
  }

  // MARK: - Release notes

  func testReleaseNotesStayShortGermanAndMakeNoPerfectionOrHardwareClaims() throws {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let url = repoRoot.appendingPathComponent("tools/release/notes/1.1.0.de.html")
    let notes = try String(contentsOf: url, encoding: .utf8)
    let lowered = notes.lowercased()

    XCTAssertLessThan(notes.count, 2_000, "short notes, not documentation")
    for phrase in forbidden + ["fehlerfrei", "getestet", "mikrofon", "100 %"] {
      XCTAssertFalse(lowered.contains(phrase), "release notes contain \(phrase)")
    }
    for topic in ["live-text", "automatik", "modelle", "updates", "optional"] {
      XCTAssertTrue(lowered.contains(topic), "release notes miss \(topic)")
    }
    XCTAssertTrue(lowered.contains("nicht lokal geprüft"), "new models are not claimed as tested")
  }

  // MARK: - Model badges

  private func installedManifest(
    sha256: String = "90ce98129eb3e8cc57e62433d500c97c624b1e3af1fcc85dd3b55ad7e0313e9f"
  ) -> LlamaCppModelStore.VerifiedManifest {
    LlamaCppModelStore.VerifiedManifest(
      modelID: "hf-ggml-org-gemma-4-e4b-it-gguf", fileName: "gemma-4-E4B-it-Q4_K_M.gguf",
      sha256: sha256, sizeBytes: 5_335_289_824, displayName: "Gemma 4 E4B",
      parameterSize: "E4B", quantization: "Q4_K_M",
      downloadURL: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/model")
  }

  func testEveryCurrentRefreshModelIsNewAndNotLocallyVerified() {
    XCTAssertEqual(LlamaCppModelCatalog.currentModels.count, 4)
    for current in LlamaCppModelCatalog.currentModels {
      XCTAssertEqual(LocalModelBadges.badges(for: current), [.new, .notLocallyVerified], current.id)
    }
  }

  func testGemmaQ40NeverInheritsTheVerificationOfTheInstalledQ4KM() throws {
    let q40 = try XCTUnwrap(
      LlamaCppModelCatalog.currentModels.first { $0.id == "gemma-4-e4b-it-q4-0" })
    let badges = LocalModelBadges.badges(for: q40)
    XCTAssertEqual(badges, [.new, .notLocallyVerified])
    XCTAssertFalse(badges.contains { if case .locallyVerified = $0 { true } else { false } })
  }

  func testTheExactInstalledGemmaQ4KMShowsTheRecordedVerificationAndIsNotNew() {
    let installed = LlamaCppModelCatalog.installedModel(from: installedManifest())
    XCTAssertEqual(
      LocalModelBadges.badges(for: installed),
      [.locallyVerified(build: "b9360", date: "2026-10-19")])
  }

  func testSameFileWithAnotherChecksumIsNotVerified() {
    let changed = installedManifest(sha256: String(repeating: "0", count: 64))
    let other = LlamaCppModelCatalog.installedModel(from: changed)
    XCTAssertEqual(LocalModelBadges.badges(for: other), [])
  }

  func testLegacyRowsCarryNoBadge() throws {
    let legacy = LlamaCppModelCatalog.models.filter { model in
      !LlamaCppModelCatalog.currentModels.contains { $0.id == model.id }
    }
    XCTAssertFalse(legacy.isEmpty)
    for model in legacy { XCTAssertEqual(LocalModelBadges.badges(for: model), [], model.id) }
  }
}
