import SwiftUI

/// Step: pre-fill the example system prompts for the E-Mail and Prompt modes, and pick the emoji
/// density for the Social mode. Prompt edits live in the view model and are persisted on advance.
struct ModesStepView: View {
  @Bindable var appState: AppState
  @Bindable var viewModel: OnboardingViewModel
  @State private var isEditingEmail = false
  @State private var isEditingPrompt = false

  var body: some View {
    VStack(alignment: .leading, spacing: OnboardingChrome.contentSpacing) {
      promptCard(
        accent: .purple,
        modeSymbol: WorkflowType.textImprover.systemImageForOnboarding,
        title: "E-Mail",
        helpText: "was rede aus deinem diktat machen soll.",
        text: $viewModel.emailPrompt,
        isEditing: $isEditingEmail
      ) {
        viewModel.restoreExample(for: .textImprover)
      }

      promptCard(
        accent: .orange,
        modeSymbol: WorkflowType.dampfAblassen.systemImageForOnboarding,
        title: "Prompt",
        helpText: "für KI-coding-agenten wie Claude Code oder Codex.",
        text: $viewModel.promptPrompt,
        isEditing: $isEditingPrompt
      ) {
        viewModel.restoreExample(for: .dampfAblassen)
      }

      socialCard
    }
  }

  private func promptCard(
    accent: Color,
    modeSymbol: String,
    title: String,
    helpText: String,
    text: Binding<String>,
    isEditing: Binding<Bool>,
    onRestore: @escaping () -> Void
  ) -> some View {
    OnboardingCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          // Canonical SF Symbol for the mode, colour-tinted (change 13)
          Image(systemName: modeSymbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent)
            // Purely decorative — duplicated by the SectionLabel text
            .accessibilityHidden(true)
          SectionLabel(text: title)
          Spacer()
          BlitzStatusPill(state: .ready, label: "preset")
        }

        Text(helpText)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)

        HStack(spacing: 8) {
          Button {
            withAnimation(.easeInOut(duration: 0.16)) { isEditing.wrappedValue.toggle() }
          } label: {
            Label(isEditing.wrappedValue ? "fertig" : "anpassen", systemImage: "pencil")
          }
          .buttonStyle(PopoverActionButtonStyle(isEditing.wrappedValue ? .primary : .secondary))

          Button("beispiel") { onRestore() }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(PopoverActionButtonStyle(.quiet))
        }

        if isEditing.wrappedValue {
          // Real text-field surface so the editor reads as editable in both colour schemes.
          TextEditor(text: text)
            .font(.system(size: 11))
            .frame(height: 96)
            .padding(6)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .scrollContentBackground(.hidden)
        }
      }
    }
  }

  private var socialCard: some View {
    OnboardingCard {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          // Canonical SF Symbol for emoji/social mode, colour-tinted (change 13)
          Image(systemName: WorkflowType.emojiText.systemImageForOnboarding)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.cyan)
            .accessibilityHidden(true)
          SectionLabel(text: "Social")
        }

        Text("wie viele emojis soll der Social-Modus einstreuen?")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)

        Picker(
          "",
          selection: Binding(
            get: { appState.modeConfig(for: .emojiText).rewrite.emojiDensity },
            set: { newValue in
              appState.updateMode(.emojiText) { $0.rewrite.emojiDensity = newValue }
            }
          )
        ) {
          ForEach(EmojiTextSettings.EmojiDensity.allCases) { density in
            Text(density.displayName).tag(density)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
      }
    }
  }
}

// MARK: - WorkflowType + onboarding symbol

extension WorkflowType {
  /// The canonical SF Symbol shown in the Modes step for each workflow type.
  /// Maps each mode to a meaningful symbol per DESIGN.md accent / mode identity.
  fileprivate var systemImageForOnboarding: String {
    switch self {
    case .transcription: return "mic.fill"
    case .localTranscription: return "lock.shield.fill"
    case .textImprover: return "envelope.fill"
    case .dampfAblassen: return "terminal.fill"
    case .emojiText: return "face.smiling.fill"
    }
  }
}
