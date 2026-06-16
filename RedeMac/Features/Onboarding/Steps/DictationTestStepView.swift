import SwiftUI

/// Step: run one safe dictation test inside onboarding. This deliberately bypasses AppState's
/// production paste workflow: no auto-paste, no archive, no memory logging.
struct DictationTestStepView: View {
  @Bindable var appState: AppState
  @State private var session: OnboardingDictationTestSession

  init(appState: AppState) {
    self.appState = appState
    _session = State(initialValue: OnboardingDictationTestSession(appState: appState))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      OnboardingCard(accent: .indigo) {
        VStack(alignment: .leading, spacing: 10) {
          SectionLabel(text: "test-diktat", icon: "mic.fill")

          Text(testHint)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 8) {
            Button {
              session.toggleRecording()
            } label: {
              Label(session.isRecording ? "stoppen" : "test starten", systemImage: buttonIcon)
            }
            .buttonStyle(PopoverActionButtonStyle(session.isRecording ? .warning : .primary))
            .disabled(!session.canStart)

            Button {
              session.reset()
            } label: {
              Label("zurücksetzen", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
            .disabled(session.transcript.isEmpty && !session.phase.isActive)
          }

          statusRow

          if !session.transcript.isEmpty {
            transcriptBox
          }
        }
      }
    }
    .onAppear { session.activate() }
    .onDisappear { session.deactivate() }
  }

  private var testHint: String {
    if appState.appSettings.secureLocalModeEnabled {
      return "sprich einen kurzen satz. die aufnahme bleibt lokal und nutzt dein geladenes Whisper-Modell."
    }
    return "sprich einen kurzen satz. audio wird für diesen test an OpenAI Whisper gesendet."
  }

  private var buttonIcon: String {
    session.isRecording ? "stop.circle.fill" : "mic.circle.fill"
  }

  private var statusRow: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: statusIcon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(statusColor)
        .frame(width: 14, height: 14)
      Text(session.statusText)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }

  private var statusIcon: String {
    switch session.phase {
    case .idle: return "circle"
    case .running: return session.isRecording ? "waveform" : "clock"
    case .variantChoice: return "clock"
    case .done: return "checkmark.circle.fill"
    case .error: return "exclamationmark.triangle.fill"
    }
  }

  private var statusColor: Color {
    switch session.phase {
    case .done: return .green
    case .error: return .orange
    case .running, .variantChoice: return .blue
    case .idle: return .secondary
    }
  }

  private var transcriptBox: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(session.transcript)
        .font(.system(size: 11.5))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6).strokeBorder(
            Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))

      Button {
        appState.copyToClipboard(session.transcript)
      } label: {
        Label("kopieren", systemImage: "doc.on.doc")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
    }
  }
}
