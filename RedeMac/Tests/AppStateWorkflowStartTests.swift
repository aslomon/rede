import Observation
import XCTest

@testable import Rede

@Observable
@MainActor
private final class StartGateWorkflow: Workflow {
  let type: WorkflowType
  var phase: WorkflowPhase
  var isRecording: Bool
  var audioLevel: Float = 0
  var didTruncateAtMaxDuration = false
  var onOutput: WorkflowOutputHandler?
  var onPhaseChange: WorkflowPhaseChangeHandler?
  var onRun: WorkflowRunHandler?

  private(set) var stopCallCount = 0
  private(set) var resetCallCount = 0
  private(set) var startCallCount = 0

  init(
    type: WorkflowType = .transcription,
    phase: WorkflowPhase = .running("aufnahme läuft ..."),
    isRecording: Bool = true
  ) {
    self.type = type
    self.phase = phase
    self.isRecording = isRecording
  }

  func start() {
    startCallCount += 1
  }

  func stop() {
    stopCallCount += 1
    isRecording = false
    phase = .done("done")
  }

  func reset() {
    resetCallCount += 1
    isRecording = false
    phase = .idle
  }
}

@MainActor
final class AppStateWorkflowStartTests: XCTestCase {
  func testStartModeSignalsBusyAndKeepsCurrentWorkflowWhenRecordingIsActive() {
    let state = AppState(prewarmEnginesAtLaunch: false)
    let workflow = StartGateWorkflow()
    var blockedMessages: [String] = []
    state.installActiveWorkflowForTesting(workflow, modeID: WorkflowType.textImprover.rawValue)
    state.onWorkflowStartBlocked = { blockedMessages.append($0) }

    let didStart = state.startMode(WorkflowType.emojiText.rawValue, source: .hotkeyBackground)

    XCTAssertFalse(didStart)
    XCTAssertEqual(blockedMessages, ["aufnahme läuft bereits"])
    XCTAssertEqual(workflow.stopCallCount, 0)
    XCTAssertEqual(workflow.resetCallCount, 0)
    XCTAssertEqual(ObjectIdentifier(state.activeWorkflow!), ObjectIdentifier(workflow))
  }

  func testToggleStopEndsCurrentRecordingWhenModeMatches() {
    let state = AppState(prewarmEnginesAtLaunch: false)
    let workflow = StartGateWorkflow()
    state.installActiveWorkflowForTesting(workflow, modeID: WorkflowType.textImprover.rawValue)

    let didStop = state.stopActiveRecordingIfCurrentMode(WorkflowType.textImprover.rawValue)

    XCTAssertTrue(didStop)
    XCTAssertEqual(workflow.stopCallCount, 1)
    XCTAssertEqual(workflow.resetCallCount, 0)
  }

  func testToggleStopRejectsDifferentModeWithoutStoppingCurrentRecording() {
    let state = AppState(prewarmEnginesAtLaunch: false)
    let workflow = StartGateWorkflow()
    state.installActiveWorkflowForTesting(workflow, modeID: WorkflowType.textImprover.rawValue)

    let didStop = state.stopActiveRecordingIfCurrentMode(WorkflowType.emojiText.rawValue)

    XCTAssertFalse(didStop)
    XCTAssertEqual(workflow.stopCallCount, 0)
    XCTAssertEqual(workflow.resetCallCount, 0)
  }
}
