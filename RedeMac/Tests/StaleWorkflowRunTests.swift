import XCTest

@testable import Rede

/// Holds a transcription worker back until the test releases it. It ignores cancellation on
/// purpose: that is the local engine which keeps running after Esc and returns later.
private actor HeldWorker {
  private var waiting: CheckedContinuation<WorkflowTranscriptionResult, Error>?
  private var early: Result<WorkflowTranscriptionResult, Error>?

  func wait() async throws -> WorkflowTranscriptionResult {
    if let early {
      self.early = nil
      return try early.get()
    }
    return try await withCheckedThrowingContinuation { waiting = $0 }
  }

  func release(_ result: Result<WorkflowTranscriptionResult, Error>) {
    if let waiting {
      self.waiting = nil
      waiting.resume(with: result)
    } else {
      early = result
    }
  }
}

private struct StubFailure: LocalizedError {
  var errorDescription: String? { "stub-failure" }
}

/// A stale run must never reach the rewrite step.
private struct ForbiddenProvider: RewriteProvider {
  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws
    -> RewriteOutcome
  {
    XCTFail("a stale run reached the rewrite provider")
    throw CancellationError()
  }
}

/// Everything a workflow can tell AppState, in order. Any entry after the old run went stale is a
/// mutation of state that belongs to a newer run (or to nobody).
@MainActor
private final class Events {
  private(set) var log: [String] = []
  func add(_ entry: String) { log.append(entry) }
}

private enum Kind: CaseIterable {
  case textImprover, dampfAblassen, emojiText, transcription
}

private enum Late: CaseIterable {
  case emptyArtifact, usableSpeech, failure

  var result: Result<WorkflowTranscriptionResult, Error> {
    switch self {
    case .emptyArtifact:
      return .success(
        WorkflowTranscriptionResult(cleanedText: "", transcriptionCompletedAt: Date()))
    case .usableSpeech:
      return .success(
        WorkflowTranscriptionResult(
          cleanedText: "Das ist ein ganz normaler Satz.", transcriptionCompletedAt: Date()))
    case .failure:
      return .failure(StubFailure())
    }
  }
}

/// What the tests need from every workflow: the microphone-free entry point and the run task.
@MainActor
private protocol DrivenFlow: Workflow {
  var processingTaskForTesting: Task<Void, Never>? { get }
  func processForTesting(audioURL: URL, recordingDuration: TimeInterval)
}

/// The rewrite workflows also report variants, a fallback note and the Automatik note.
@MainActor
private protocol RewriteFlow: DrivenFlow {
  var onVariants: WorkflowVariantChoiceHandler? { get set }
  var onRewriteFallback: WorkflowRewriteFallbackHandler? { get set }
  var onRoutingNote: ((PurposeRoutingNote?) -> Void)? { get set }
}

extension TextImprovementWorkflow: RewriteFlow {}
extension DampfAblassenWorkflow: RewriteFlow {}
extension EmojiTextWorkflow: RewriteFlow {}
extension TranscriptionWorkflow: DrivenFlow {}

/// One workflow under test plus the two held workers it can be handed (old run, new run).
@MainActor
private final class Rig {
  let events = Events()
  let oldWorker = HeldWorker()
  let newWorker = HeldWorker()
  let oldURL = URL(fileURLWithPath: "/nonexistent-rede-test/old.m4a")
  let newURL = URL(fileURLWithPath: "/nonexistent-rede-test/new.m4a")
  private let flow: any DrivenFlow

  var workflow: any Workflow { flow }
  var currentTask: Task<Void, Never>? { flow.processingTaskForTesting }
  func process(_ url: URL) { flow.processForTesting(audioURL: url, recordingDuration: 2) }

  init(_ kind: Kind) {
    let oldWorker = oldWorker
    let newWorker = newWorker
    let oldURL = oldURL
    flow = Self.makeFlow(kind) { url, _ in
      if url == oldURL { return try await oldWorker.wait() }
      return try await newWorker.wait()
    }
    wireEvents()
  }

  private static func makeFlow(
    _ kind: Kind, _ injected: @escaping WorkflowTranscriptionOverride
  ) -> any DrivenFlow {
    let provider = ForbiddenProvider()
    let rewrite = RewriteConfig()
    switch kind {
    case .textImprover:
      return TextImprovementWorkflow(
        rewrite: rewrite, provider: provider, transcriptionOverride: injected)
    case .dampfAblassen:
      return DampfAblassenWorkflow(
        rewrite: rewrite, provider: provider, transcriptionOverride: injected)
    case .emojiText:
      return EmojiTextWorkflow(
        rewrite: rewrite, provider: provider, transcriptionOverride: injected)
    case .transcription:
      return TranscriptionWorkflow(transcriptionOverride: injected)
    }
  }

  private func wireEvents() {
    let events = events
    flow.onPhaseChange = { events.add("phase:\($0)") }
    flow.onOutput = { events.add("output:\($0)") }
    flow.onRun = { _ in events.add("run") }
    guard let rewrite = flow as? any RewriteFlow else { return }
    rewrite.onVariants = { _ in events.add("variants") }
    rewrite.onRewriteFallback = { _ in events.add("fallback") }
    rewrite.onRoutingNote = { _ in MainActor.assumeIsolated { events.add("routing") } }
  }
}

/// A transcription worker that finishes late, after Esc/reset or after a newer run started, must
/// not touch phase, error, output, archive record or the routing note of anything current.
@MainActor
final class StaleWorkflowRunTests: XCTestCase {
  func testWorkerFinishingAfterResetLeavesNoTrace() async {
    for kind in Kind.allCases {
      for late in Late.allCases {
        let rig = Rig(kind)
        rig.process(rig.oldURL)
        let oldTask = rig.currentTask

        rig.workflow.reset()
        let afterReset = rig.events.log
        await rig.oldWorker.release(late.result)
        await oldTask?.value

        XCTAssertEqual(rig.events.log, afterReset, "\(kind) \(late)")
        XCTAssertEqual(rig.workflow.phase, .idle, "\(kind) \(late)")
      }
    }
  }

  func testWorkerOfASupersededRunLeavesTheNewRunUntouched() async {
    for kind in Kind.allCases {
      for late in Late.allCases {
        let rig = Rig(kind)
        rig.process(rig.oldURL)
        let oldTask = rig.currentTask
        rig.process(rig.newURL)
        let newTask = rig.currentTask
        let runningPhase = rig.workflow.phase
        let beforeLateResult = rig.events.log

        await rig.oldWorker.release(late.result)
        await oldTask?.value

        XCTAssertEqual(rig.events.log, beforeLateResult, "\(kind) \(late)")
        XCTAssertEqual(rig.workflow.phase, runningPhase, "\(kind) \(late)")

        rig.workflow.reset()
        await rig.newWorker.release(.failure(CancellationError()))
        await newTask?.value
      }
    }
  }

  func testTheCurrentRunStillReportsItsOwnNoSpeechAndFailure() async {
    let expected: [(Late, WorkflowPhase)] = [
      (.emptyArtifact, .error(TranscriptionQualityService.noSpeechMessage)),
      (.failure, .error("stub-failure")),
    ]
    for kind in Kind.allCases {
      for (late, phase) in expected {
        let rig = Rig(kind)
        rig.process(rig.oldURL)
        let task = rig.currentTask

        await rig.oldWorker.release(late.result)
        await task?.value

        XCTAssertEqual(rig.workflow.phase, phase, "\(kind) \(late)")
      }
    }
  }
}
