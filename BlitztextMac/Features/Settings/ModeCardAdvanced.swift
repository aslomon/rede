import SwiftUI

// MARK: - ModeCardView advanced + emoji subviews
//
// The "Erweitert" disclosure of a mode card: tone, custom prompt, context, reply-context,
// memory toggle and the reset footer — plus the always-basic emoji-density picker. Split out of
// `ModeCardView.swift` to keep each file compact (DESIGN.md / code-quality rules).
extension ModeCardView {

  // MARK: - Tone / Prompt / Context / Reply

  var tonePicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("schreibstil")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker("", selection: bind(\.rewrite.tone)) {
        ForEach(TextImprovementSettings.TextTone.allCases) { tone in
          Text(tone.displayName).tag(tone)
        }
      }
      .pickerStyle(.segmented)
      .disabled(hasCustomPrompt)
    }
  }

  var systemPromptEditor: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("eigene anweisung")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      TextEditor(text: bind(\.rewrite.systemPrompt))
        .font(.system(size: 11))
        .frame(height: 96)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6).strokeBorder(
            Color.primary.opacity(0.06), lineWidth: 0.5))
    }
  }

  var contextField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("kontext")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      TextField("z. B. \"E-Mails im bereich unternehmensberatung\"", text: bind(\.rewrite.context))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
        .disabled(hasCustomPrompt)
    }
  }

  var replyContextPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("markierten text einbeziehen")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker("", selection: bind(\.rewrite.replyContextMode)) {
        ForEach(ReplyContextMode.allCases) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .pickerStyle(.menu)
      if config.rewrite.replyContextMode != .off {
        InfoDisclosure("kontext-details") {
          Text(
            "liest die aktuelle auswahl in der app und bezieht sie als kontext ein. bei OpenAI-Verarbeitung wird der markierte text mitgesendet."
          )
        }
      }
    }
  }

  var emojiDensityPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("emoji-dichte")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Picker("", selection: bind(\.rewrite.emojiDensity)) {
        ForEach(EmojiTextSettings.EmojiDensity.allCases) { density in
          Text(density.displayName).tag(density)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  // MARK: - Memory context (rewrite modes only)

  @ViewBuilder
  var automaticFieldContextToggle: some View {
    Toggle("fensterkontext automatisch lesen", isOn: bind(\.rewrite.useAutomaticFieldContext))
      .toggleStyle(.switch)
      .controlSize(.small)
      .font(.system(size: 11))
  }

  @ViewBuilder
  var unifiedMemoryControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle("memory nutzen", isOn: unifiedMemoryBinding)
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11))

      if type == .textImprover, config.rewrite.useSemanticEmailMemory {
        Picker("", selection: bind(\.rewrite.semanticEmailEnrichmentLevel)) {
          ForEach(SemanticEmailEnrichmentLevel.allCases) { level in
            Text(level.displayName).tag(level)
          }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
      }
    }
  }

  private var unifiedMemoryBinding: Binding<Bool> {
    Binding(
      get: {
        if type == .textImprover {
          return config.rewrite.useMemoryContext || config.rewrite.useSemanticEmailMemory
        }
        return config.rewrite.useMemoryContext
      },
      set: { value in
        appState.updateMode(id: modeID) { mode in
          mode.rewrite.useMemoryContext = value
          if type == .textImprover {
            mode.rewrite.useSemanticEmailMemory = value
          }
        }
      }
    )
  }

  @ViewBuilder
  var variantChoiceToggle: some View {
    Toggle("immer zwei versionen zeigen", isOn: bind(\.rewrite.showTwoVariants))
      .toggleStyle(.switch)
      .controlSize(.small)
      .font(.system(size: 11))
  }
}
