import XCTest

@testable import Rede

/// Guards the off-main settings write path: `SecureFileWriter` must write atomically, round-trip
/// the bytes, and enforce owner-only 0600 permissions even when overwriting an existing file.
/// The debounced settings save hands a Sendable snapshot to this writer off the MainActor, so a
/// regression here would silently corrupt persistence or leak PII as group/other-readable.
final class SecureFileWriterTests: XCTestCase {

  private var tempURL: URL!

  override func setUpWithError() throws {
    let dir = FileManager.default.temporaryDirectory
    tempURL = dir.appendingPathComponent("secure-write-\(UUID().uuidString).json")
  }

  override func tearDownWithError() throws {
    if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
  }

  /// A written payload reads back byte-for-byte (the encode → write → decode contract).
  func testWriteRoundTripsBytes() throws {
    let payload = Data("{\"hello\":\"world\"}".utf8)
    try SecureFileWriter.write(payload, to: tempURL)

    let readBack = try Data(contentsOf: tempURL)
    XCTAssertEqual(readBack, payload)
  }

  /// The file must be owner-only (0600), both on create AND on overwrite of an existing file.
  func testWriteEnforces0600PermissionsOnCreateAndOverwrite() throws {
    try SecureFileWriter.write(Data("first".utf8), to: tempURL)
    try assertPermissions(equal: 0o600)

    // Overwriting an existing file must re-tighten the permissions, not inherit a looser mode.
    try SecureFileWriter.write(Data("second-longer-payload".utf8), to: tempURL)
    try assertPermissions(equal: 0o600)

    let readBack = try Data(contentsOf: tempURL)
    XCTAssertEqual(readBack, Data("second-longer-payload".utf8))
  }

  private func assertPermissions(equal expected: Int) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
    let perms = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
    XCTAssertEqual(perms.intValue, expected)
  }
}
