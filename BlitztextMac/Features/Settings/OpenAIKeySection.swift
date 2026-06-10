import AppKit
import SwiftUI

/// Self-contained "OpenAI API Key" surface: masked display + edit/paste, validation, and the
/// "Speichern" button (which belongs to the key). Owns its own state so it can be dropped into any
/// settings tab. Lives in the Modelle tab next to the local engines.
struct OpenAIKeySection: View {
  private static let openAIAPIKeyPattern = #"^sk-[A-Za-z0-9_-]{20,}$"#

  @Bindable var appState: AppState

  private enum FieldFocus {
    case openAIAPIKey
  }

  @State private var apiKey = ""
  @State private var editing = false
  @State private var saved = false
  @State private var errorText: String?
  @FocusState private var focused: FieldFocus?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        SectionLabel(text: "OpenAI API Key")
        Spacer()
        if appState.hasValue(for: .openAIAPIKey) && !editing {
          // spec #5: 'ändern' in header slot
          Button {
            editing = true
          } label: {
            Label("ändern", systemImage: "pencil")
          }
          .buttonStyle(PopoverActionButtonStyle(.quiet))
        } else if editing && appState.hasValue(for: .openAIAPIKey) {
          // spec #5: 'abbrechen' replaces 'ändern' when editing=true and a key already exists
          Button {
            apiKey = ""
            editing = false
            errorText = nil
          } label: {
            Label("abbrechen", systemImage: "xmark")
          }
          .buttonStyle(PopoverActionButtonStyle(.quiet))
        }
      }

      if appState.hasValue(for: .openAIAPIKey) && !editing {
        maskedKey
      } else {
        keyEntryRow
        // spec #5: 'Speichern' anchored directly below the key entry row, before InfoDisclosure
        saveButton
      }

      // spec #2: full explanation moved into InfoDisclosure
      InfoDisclosure("warum?") {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            "ohne key bleiben die online-modelle deaktiviert. "
              + "trage deinen OpenAI-Key ein, um sie für transkription und umschreiben zu nutzen."
          )
          Text(
            "dein key bleibt lokal in dieser app. "
              + "audio und text werden direkt an die OpenAI-API gesendet."
          )
        }
      }

      if let errorText {
        Text(errorText)
          .font(.system(size: 10.5))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onAppear {
      if !appState.hasValue(for: .openAIAPIKey) {
        editing = true
        focused = .openAIAPIKey
      }
    }
  }

  private var maskedKey: some View {
    HStack(spacing: 6) {
      Image(systemName: "lock.fill")
        .font(.system(size: 9))
        .foregroundStyle(.green.opacity(0.8))
      Text(appState.apiKeyDisplayValue(for: .openAIAPIKey))
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
  }

  private var keyEntryRow: some View {
    HStack(spacing: 8) {
      SecureField("sk-...", text: $apiKey)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11.5))
        .focused($focused, equals: .openAIAPIKey)

      Button("einfügen") {
        pasteAPIKeyFromClipboard()
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
    }
  }

  // spec #5: PopoverActionButtonStyle(.primary) provides correct white foreground —
  // manual .foregroundStyle overrides removed.
  private var saveButton: some View {
    HStack {
      Spacer()
      Button {
        save()
      } label: {
        if saved {
          Label("gespeichert", systemImage: "checkmark")
            .font(.system(size: 12, weight: .medium))
        } else {
          Text("speichern")
            .font(.system(size: 12, weight: .medium))
        }
      }
      .buttonStyle(PopoverActionButtonStyle(saved ? .secondary : .primary))
      .animation(.easeInOut(duration: 0.2), value: saved)
    }
  }

  private func save() {
    errorText = nil
    KeychainService.invalidateCache()
    let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

    if editing || !appState.hasValue(for: .openAIAPIKey) {
      guard !trimmedAPIKey.isEmpty else {
        errorText = "bitte trage deinen OpenAI API Key ein."
        return
      }
      do {
        try KeychainService.save(key: .openAIAPIKey, value: trimmedAPIKey)
        apiKey = ""
        editing = false
      } catch {
        errorText = "OpenAI API Key konnte nicht gespeichert werden."
        return
      }
    }

    KeychainService.invalidateCache()
    if !appState.hasValue(for: .openAIAPIKey) {
      errorText =
        "OpenAI API Key wurde nicht persistent gespeichert. bitte app neu starten und erneut versuchen."
      return
    }

    withAnimation(.easeInOut(duration: 0.2)) { saved = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      withAnimation(.easeInOut(duration: 0.2)) { saved = false }
    }
  }

  private func pasteAPIKeyFromClipboard() {
    guard let rawText = NSPasteboard.general.string(forType: .string) else {
      errorText = "zwischenablage enthält keinen text."
      return
    }

    let firstLine = rawText.components(separatedBy: .newlines).first ?? rawText
    let trimmedKey = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedKey.range(of: Self.openAIAPIKeyPattern, options: .regularExpression) != nil else {
      errorText = "zwischenablage enthält keinen plausiblen OpenAI API Key."
      return
    }

    apiKey = trimmedKey
    NSPasteboard.general.clearContents()
    errorText = nil
  }
}
