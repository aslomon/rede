import XCTest

@testable import Rede

/// Secure-local must be enforced inside every OpenAI client, per attempt, from one composition
/// root. These tests pin the gate's behavior and scan production sources for clients built
/// without it.
final class RemoteAccessGateTests: XCTestCase {
  func testGateStartsClosedBecauseSecureLocalDefaultsToOn() {
    XCTAssertTrue(AppSettings().secureLocalModeEnabled)
    XCTAssertFalse(RemoteAccessGate().allowsRemote())
  }

  func testInjectedClosureReadsTheCurrentPolicyOnEveryCall() {
    let gate = RemoteAccessGate(secureLocalEnabled: false)
    let check = gate.allowsRemote

    XCTAssertTrue(check())
    gate.update(secureLocalEnabled: true)
    XCTAssertFalse(check(), "a Bool captured at creation would still say true")
    gate.update(secureLocalEnabled: false)
    XCTAssertTrue(check())
  }

  func testGateIsSafeToReadFromManyThreads() async {
    let gate = RemoteAccessGate(secureLocalEnabled: true)
    let check = gate.allowsRemote
    await withTaskGroup(of: Bool.self) { group in
      for index in 0..<200 {
        group.addTask {
          if index == 100 { gate.update(secureLocalEnabled: false) }
          return check()
        }
      }
      for await _ in group {}
    }
    XCTAssertTrue(check())
  }

  // MARK: - Production construction guard

  /// Every production construction of an OpenAI client must pass `isRemoteAllowed`. The Decisions
  /// client and its transport are included: a default-built one carries an always-true gate that
  /// only the router's own checks would hide. Nothing is allowlisted.
  func testProductionClientsAreAlwaysBuiltWithTheGate() throws {
    let guardedCalls = [
      "OpenAIRewriteProvider(", "TranscriptionService.transcribe(",
      "fetchAvailableChatModels(", "LiveTranscriptionController(", "DecisionsPurposeRouter(",
      "DecisionsClient(", "OpenAIDecisionsTransport("
    ]
    var violations: [String] = []
    for file in try productionSwiftFiles() {
      let source = try String(contentsOf: file, encoding: .utf8)
      for token in guardedCalls {
        for call in Self.callExpressions(of: token, in: source)
        where !call.contains("isRemoteAllowed") {
          violations.append("\(file.lastPathComponent): \(token)")
        }
      }
    }
    XCTAssertEqual(violations, [], "client built without isRemoteAllowed")
  }

  /// Outside the Decisions services, only the composition root may build the router, the client
  /// or the transport, and it must hand the router an explicit gated client.
  func testDecisionsEntryPointsAreBuiltOnlyByTheCompositionRoot() throws {
    let root = "AppState+RemoteAccess.swift"
    var offenders: [String] = []
    for file in try productionSwiftFiles()
    where !file.path.contains("/Services/") && file.lastPathComponent != root {
      let source = try String(contentsOf: file, encoding: .utf8)
      for token in ["DecisionsClient(", "DecisionsPurposeRouter(", "OpenAIDecisionsTransport("]
      where !Self.callExpressions(of: token, in: source).isEmpty {
        offenders.append("\(file.lastPathComponent): \(token)")
      }
    }
    XCTAssertEqual(offenders, [])

    let source = try String(contentsOf: try compositionRootURL(), encoding: .utf8)
    let routerCalls = Self.callExpressions(of: "DecisionsPurposeRouter(", in: source)
    XCTAssertEqual(routerCalls.count, 1, "exactly one router construction")
    XCTAssertTrue(
      routerCalls.allSatisfy { $0.contains("client:") && $0.contains("isRemoteAllowed:") },
      "the router needs an explicit client AND the gate")
    XCTAssertTrue(
      Self.callExpressions(of: "DecisionsClient(", in: source)
        .allSatisfy { $0.contains("isRemoteAllowed:") })
  }

  func testCallScannerIgnoresCommentsAndDeclarationsButSeesRealCalls() {
    let source = """
      // DecisionsClient() in a comment
      func DecisionsClient(x: Int) {}
      let a = DecisionsClient()
      let b = DecisionsClient(isRemoteAllowed: gate)
      """
    let calls = Self.callExpressions(of: "DecisionsClient(", in: source)
    XCTAssertEqual(calls, ["DecisionsClient()", "DecisionsClient(isRemoteAllowed: gate)"])
  }

  private func compositionRootURL() throws -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("App/AppState+RemoteAccess.swift")
  }

  private func productionSwiftFiles() throws -> [URL] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    var files: [URL] = []
    for folder in ["App", "Features", "Services", "Views"] {
      let enumerator = FileManager.default.enumerator(
        at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        if url.pathExtension == "swift" { files.append(url) }
      }
    }
    XCTAssertFalse(files.isEmpty, "source scan found no files")
    return files
  }

  /// Text of each call `token(...)` including its balanced argument list. Declarations
  /// (`func name(`) and comment lines are skipped.
  static func callExpressions(of token: String, in source: String) -> [String] {
    var calls: [String] = []
    var searchStart = source.startIndex
    while let range = source.range(of: token, range: searchStart..<source.endIndex) {
      searchStart = range.upperBound
      let lineStart =
        source[..<range.lowerBound].lastIndex(of: "\n").map { source.index(after: $0) }
        ?? source.startIndex
      let prefix = source[lineStart..<range.lowerBound]
      if prefix.contains("//") || prefix.hasSuffix("func ") { continue }
      var depth = 1
      var end = range.upperBound
      while end < source.endIndex, depth > 0 {
        if source[end] == "(" { depth += 1 } else if source[end] == ")" { depth -= 1 }
        end = source.index(after: end)
      }
      calls.append(String(source[range.lowerBound..<end]))
    }
    return calls
  }
}
