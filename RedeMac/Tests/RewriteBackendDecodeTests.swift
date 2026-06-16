import XCTest

@testable import Rede

/// Sprint 1 (Phase 2) renamed the on-device rewrite backend from `appleIntelligence` to
/// `.local`. Legacy `settings.json` files persisted the raw string "appleIntelligence";
/// they must decode onto `.local` with zero data loss. Unknown strings fall back to `.openai`.
final class RewriteBackendDecodeTests: XCTestCase {

  private func decodeBackend(rawValue raw: String) throws -> RewriteBackend {
    let json = """
      { "rewriteBackend": "\(raw)" }
      """
    let config = try JSONDecoder().decode(RewriteConfig.self, from: Data(json.utf8))
    return config.rewriteBackend
  }

  // MARK: - Tolerant decoder mapping

  func testLegacyAppleIntelligenceDecodesToLocal() throws {
    XCTAssertEqual(try decodeBackend(rawValue: "appleIntelligence"), .local)
  }

  func testLocalDecodesDirectly() throws {
    XCTAssertEqual(try decodeBackend(rawValue: "local"), .local)
  }

  func testOpenAIDecodesDirectly() throws {
    XCTAssertEqual(try decodeBackend(rawValue: "openai"), .openai)
  }

  func testUnknownRawValueFallsBackToOpenAI() throws {
    XCTAssertEqual(try decodeBackend(rawValue: "totallyBogusBackend"), .openai)
  }

  /// The static helper is the seam the decoder uses; assert it directly too.
  func testFromRawValueHelperMapping() {
    XCTAssertEqual(RewriteBackend.from(rawValue: "appleIntelligence"), .local)
    XCTAssertEqual(RewriteBackend.from(rawValue: "local"), .local)
    XCTAssertEqual(RewriteBackend.from(rawValue: "openai"), .openai)
    XCTAssertEqual(RewriteBackend.from(rawValue: ""), .openai)
    XCTAssertEqual(RewriteBackend.from(rawValue: "appleintelligence"), .openai)  // case-sensitive
  }

  // MARK: - Missing key defaults

  func testMissingBackendKeyDefaultsToOpenAI() throws {
    let config = try JSONDecoder().decode(RewriteConfig.self, from: Data("{}".utf8))
    XCTAssertEqual(config.rewriteBackend, .openai)
  }

  // MARK: - Round-trip stability for the renamed case

  /// Encoding `.local` and decoding it back stays `.local` (no re-introduction of the legacy name).
  func testLocalRoundTripStaysLocal() throws {
    let original = RewriteConfig(rewriteBackend: .local)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RewriteConfig.self, from: data)
    XCTAssertEqual(decoded.rewriteBackend, .local)
  }

  func testLabelIsLokal() {
    // rede voice: user-visible picker labels are consistently lowercase (DESIGN.md).
    XCTAssertEqual(RewriteBackend.local.displayName, "lokal")
  }
}
