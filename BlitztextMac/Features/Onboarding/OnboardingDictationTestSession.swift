import Foundation
import Observation

@Observable
@MainActor
final class OnboardingDictationTestSession {
  var phase: WorkflowPhase = .idle
  var transcript = ""

  private let makeWorkflow: @MainActor () -> any Workflow
  private let setHotkeysSuspended: @MainActor (Bool) -> Void
  private var workflow: (any Workflow)?

  init(
    makeWorkflow: @escaping @MainActor () -> any Workflow,
    setHotkeysSuspended: @escaping @MainActor (Bool) -> Void
  ) {
    self.makeWorkflow = makeWorkflow
    self.setHotkeysSuspended = setHotkeysSuspended
  }

  convenience init(appState: AppState) {
    self.init(
      makeWorkflow: {
        TranscriptionWorkflow(
          type: .transcription,
          customTerms: appState.effectiveCustomTerms,
          dictionary: appState.appSettings.dictationDictionary,
          fuzzyTerms: appState.effectiveFuzzyTerms,
          language: appState.transcriptionSettings.language,
          backend: appState.appSettings.secureLocalModeEnabled ? .local : .remote,
          localModelName: appState.selectedLocalModelName
        )
      },
      setHotkeysSuspended: { isSuspended in
        appState.setHotkeyRecordingActive(isSuspended)
      }
    )
  }

  var isRecording: Bool { workflow?.isRecording ?? false }

  var canStart: Bool {
    switch phase {
    case .idle, .done, .error:
      return true
    case .running, .variantChoice:
      return isRecording
    }
  }

  var statusText: String {
    switch phase {
    case .idle:
      return "bereit für einen kurzen test."
    case .running(let message):
      return message
    case .variantChoice:
      return "test läuft …"
    case .done:
      return "transkript ist bereit."
    case .error(let message):
      return message
    }
  }

  func activate() {
    setHotkeysSuspended(true)
  }

  func deactivate() {
    reset()
    setHotkeysSuspended(false)
  }

  func toggleRecording() {
    if workflow?.isRecording == true {
      workflow?.stop()
      return
    }

    let newWorkflow = makeWorkflow()
    configure(newWorkflow)
    workflow = newWorkflow
    transcript = ""
    newWorkflow.start()
  }

  func reset() {
    workflow?.reset()
    workflow = nil
    transcript = ""
    phase = .idle
  }

  private func configure(_ workflow: any Workflow) {
    workflow.onRun = nil
    workflow.onOutput = { [weak self] text in
      self?.transcript = text
    }
    workflow.onPhaseChange = { [weak self] phase in
      self?.phase = phase
    }
  }
}
