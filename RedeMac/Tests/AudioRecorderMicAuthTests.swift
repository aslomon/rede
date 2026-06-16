import XCTest

@testable import Rede

/// Pins the pure mic-authorization → error-message mapping that gates `AudioRecorder.startRecording()`.
/// A denied/restricted grant (folded into `.denied`) or a never-asked grant must NOT start a dead,
/// silent recording — it returns a clear German hint instead; only `.granted` returns `nil` (proceed).
@MainActor
final class AudioRecorderMicAuthTests: XCTestCase {

  func testGrantedProceedsWithNoMessage() {
    XCTAssertNil(AudioRecorder.recordingBlockedMessage(for: .granted))
  }

  func testDeniedReturnsSystemSettingsHint() {
    XCTAssertEqual(
      AudioRecorder.recordingBlockedMessage(for: .denied),
      AudioRecorder.micDeniedMessage
    )
    XCTAssertTrue(AudioRecorder.micDeniedMessage.contains("Systemeinstellungen"))
  }

  func testNotDeterminedReturnsPendingHint() {
    XCTAssertEqual(
      AudioRecorder.recordingBlockedMessage(for: .notDetermined),
      AudioRecorder.micPendingMessage
    )
  }

  /// The two blocking states must produce distinct, non-empty user-facing messages.
  func testBlockingMessagesAreDistinctAndNonEmpty() {
    let denied = AudioRecorder.recordingBlockedMessage(for: .denied)
    let pending = AudioRecorder.recordingBlockedMessage(for: .notDetermined)
    XCTAssertNotNil(denied)
    XCTAssertNotNil(pending)
    XCTAssertNotEqual(denied, pending)
    XCTAssertFalse(denied?.isEmpty ?? true)
    XCTAssertFalse(pending?.isEmpty ?? true)
  }
}
