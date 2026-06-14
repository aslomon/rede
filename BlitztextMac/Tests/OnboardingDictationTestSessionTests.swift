import Observation
import XCTest

@testable import Blitztext

@Observable
@MainActor
private final class FakeOnboardingWorkflow: Workflow {
  let type: WorkflowType = .transcription
  var phase: WorkflowPhase = .idle {
    didSet { onPhaseChange?(phase) }
  }
  var isRecording = false
  var audioLevel: Float = 0
  var didTruncateAtMaxDuration = false
  var onOutput: WorkflowOutputHandler?
  var onPhaseChange: WorkflowPhaseChangeHandler?
  var onRun: WorkflowRunHandler?

  private(set) var didReset = false

  func start() {
    isRecording = true
    phase = .running("aufnahme läuft …")
  }

  func stop() {
    isRecording = false
    phase = .done("Hallo rede")
    onOutput?("Hallo rede")
  }

  func reset() {
    isRecording = false
    didReset = true
    phase = .idle
  }
}

@MainActor
final class OnboardingDictationTestSessionTests: XCTestCase {
  func testOutputStaysInSessionAndRunHandlerIsNotWired() {
    let workflow = FakeOnboardingWorkflow()
    let session = OnboardingDictationTestSession(
      makeWorkflow: { workflow },
      setHotkeysSuspended: { _ in }
    )

    session.toggleRecording()
    XCTAssertTrue(session.isRecording)
    XCTAssertNil(workflow.onRun)

    session.toggleRecording()
    XCTAssertEqual(session.transcript, "Hallo rede")
    XCTAssertEqual(session.phase, .done("Hallo rede"))
  }

  func testActivateAndDeactivateSuspendHotkeysAndResetWorkflow() {
    let workflow = FakeOnboardingWorkflow()
    var suspensionEvents: [Bool] = []
    let session = OnboardingDictationTestSession(
      makeWorkflow: { workflow },
      setHotkeysSuspended: { suspensionEvents.append($0) }
    )

    session.activate()
    session.toggleRecording()
    session.deactivate()

    XCTAssertEqual(suspensionEvents, [true, false])
    XCTAssertTrue(workflow.didReset)
    XCTAssertFalse(session.isRecording)
    XCTAssertEqual(session.phase, .idle)
  }
}
