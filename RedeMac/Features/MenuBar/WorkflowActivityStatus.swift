import SwiftUI

/// Recording remains in the floating pill; navigation only carries a quiet status line.
struct WorkflowActivityStatus: View {
  let appState: AppState

  var body: some View {
    if let workflow = appState.activeWorkflow, workflow.phase.isActive {
      HStack(spacing: 6) {
        Image(systemName: workflow.isRecording ? "mic.fill" : "waveform")
          .foregroundStyle(RedeBrand.violet)
        Text(workflow.isRecording ? "aufnahme läuft" : "wird verarbeitet …")
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      .font(.system(size: 10.5, weight: .medium))
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .accessibilityElement(children: .combine)
    }
  }
}
