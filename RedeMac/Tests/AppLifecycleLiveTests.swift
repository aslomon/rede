import AppKit
import XCTest

@testable import Rede

/// Behaves like the real controller: cancel is idempotent and a cancelled session finishes as
/// `.cancelled`; otherwise it delivers its transcript. No socket, no microphone.
@MainActor
private final class FakeLiveSession: LiveSessionControlling {
  var snapshot = LiveTranscriptSnapshot()
  var phase: LiveTranscriptionController.Phase = .streaming
  private(set) var cancelCalls = 0
  private(set) var isCancelled = false

  func begin(_ configuration: LiveConfiguration) {}

  func finish() async -> LiveOutcome {
    isCancelled ? .cancelled : .transcript("Hallo Welt", LiveStats())
  }

  func cancel() {
    cancelCalls += 1
    isCancelled = true
    phase = .cancelled
  }
}

/// Focus loss must leave a running dictation alone; only shutdown closes the live session. Both
/// events still flush settings. AppState gets a private notification center and a temp settings
/// file, so the real app, the real center and the real settings are never touched.
@MainActor
final class AppLifecycleLiveTests: XCTestCase {
  private struct Rig {
    let state: AppState
    let center: NotificationCenter
    let session: FakeLiveSession
    let live: WorkflowLiveSupport
    let settingsFile: URL
  }

  private func makeRig(withLive: Bool = true) throws -> Rig {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rede-lifecycle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("settings.json")

    var settings = AppSettings()
    settings.didMigrateToModeConfigs = true
    settings.modesSchemaVersion = 4
    settings.hasAutoSelectedFastLocalModel = true
    settings.hadAccessibilityGrant = true
    let center = NotificationCenter()
    let state = AppState(
      appSettings: settings, transcriptionSettings: TranscriptionSettings(),
      textImprovementSettings: TextImprovementSettings(),
      dampfAblassenSettings: DampfAblassenSettings(), emojiTextSettings: EmojiTextSettings(),
      prewarmEnginesAtLaunch: false, credentialPresence: { _ in true },
      settingsFileURL: file, lifecycleCenter: center)

    let session = FakeLiveSession()
    let live = WorkflowLiveSupport(makeSession: { session })
    live.begin(language: "de", keywords: [])
    state.installActiveLiveForTesting(withLive ? live : nil)
    return Rig(state: state, center: center, session: session, live: live, settingsFile: file)
  }

  /// Posts on the rig's private center and waits until the main-queue observer has run: the
  /// observer was queued first and the main queue is serial, so our operation runs after it.
  private func post(_ name: Notification.Name, _ rig: Rig) async {
    rig.center.post(name: name, object: nil)
    await withCheckedContinuation { continuation in
      OperationQueue.main.addOperation { continuation.resume() }
    }
  }

  private func settingsFileContains(_ marker: String, _ rig: Rig) -> Bool {
    guard let data = try? Data(contentsOf: rig.settingsFile) else { return false }
    return String(decoding: data, as: UTF8.self).contains(marker)
  }

  func testFocusLossKeepsLiveRunningAndStillFlushesSettings() async throws {
    let rig = try makeRig()
    rig.state.appSettings.userDisplayName = "focus-marker"

    await post(NSApplication.willResignActiveNotification, rig)

    XCTAssertEqual(rig.session.cancelCalls, 0, "ordinary focus loss must not cancel Live")
    XCTAssertFalse(rig.session.isCancelled)
    XCTAssertTrue(settingsFileContains("focus-marker", rig), "focus loss still flushes settings")

    // The user stops later: Live still delivers, so the run does not terminal-abort.
    let text = try await rig.live.finalTranscript()
    XCTAssertEqual(text, "Hallo Welt")
  }

  func testTerminationCancelsLiveAndStillFlushesSettings() async throws {
    let rig = try makeRig()
    rig.state.appSettings.userDisplayName = "quit-marker"

    await post(NSApplication.willTerminateNotification, rig)

    XCTAssertEqual(rig.session.cancelCalls, 1)
    XCTAssertTrue(rig.session.isCancelled)
    XCTAssertTrue(settingsFileContains("quit-marker", rig), "shutdown still flushes settings")
    do {
      _ = try await rig.live.finalTranscript()
      XCTFail("a cancelled live session is terminal for the run")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }

  func testCancelStaysTerminalAndIdempotentAcrossShutdownAndReset() async throws {
    let rig = try makeRig()

    await post(NSApplication.willTerminateNotification, rig)
    await post(NSApplication.willTerminateNotification, rig)
    rig.live.cancel()  // what a workflow reset does after the app already cancelled

    XCTAssertTrue(rig.session.isCancelled)
    XCTAssertEqual(rig.session.phase, .cancelled)
    do {
      _ = try await rig.live.finalTranscript()
      XCTFail("still terminal after repeated cancels")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }

  func testShutdownWithoutALiveSessionOnlyFlushes() async throws {
    let rig = try makeRig(withLive: false)
    rig.state.appSettings.userDisplayName = "no-live-marker"

    await post(NSApplication.willTerminateNotification, rig)

    XCTAssertEqual(rig.session.cancelCalls, 0)
    XCTAssertTrue(settingsFileContains("no-live-marker", rig))
  }
}
