import XCTest

@testable import Blitztext

final class LlamaCppRuntimeTests: XCTestCase {
  func testLaunchArgumentsBindOnlyToLocalhost() throws {
    let binaryURL = URL(fileURLWithPath: "/tmp/llama-server")
    let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")

    let arguments = LlamaCppRuntimeService.launchArguments(
      modelURL: modelURL,
      port: 49123,
      alias: "blitztext-local",
      contextSize: 4096,
      apiKey: "token"
    )

    XCTAssertTrue(arguments.contains("--host"))
    XCTAssertTrue(arguments.contains("127.0.0.1"))
    XCTAssertFalse(arguments.contains("0.0.0.0"))
    XCTAssertTrue(arguments.contains("--api-key"))
    XCTAssertTrue(arguments.contains("token"))
    XCTAssertEqual(LlamaCppRuntimeService.executableURLOverride(binaryURL), binaryURL)
  }

  func testFreePortSelectionAvoidsPrivilegedPorts() throws {
    let port = try LlamaCppRuntimeService.findFreeLocalPort()

    XCTAssertGreaterThanOrEqual(port, 49152)
    XCTAssertLessThanOrEqual(port, 65535)
  }

  func testStopWithoutRunningProcessIsIdempotent() async throws {
    let runtime = LlamaCppRuntimeService()

    try await runtime.stop()
    try await runtime.stop()
  }

  func testListeningPIDParserIgnoresInvalidLines() {
    XCTAssertEqual(
      LlamaCppRuntimeService.parseListeningPIDs("123\nnot-a-pid\n456\n"),
      Set([123, 456])
    )
  }
}
