import AppKit
import SwiftUI

/// Self-contained "OpenAI API Key" surface: masked display + edit, validation, and the
/// "Speichern" button (which belongs to the key). Owns its own state so it can be dropped into any
/// settings tab. Lives in the Modelle tab next to the local engines.
struct OpenAIKeySection: View {
  private static let openAIAPIKeyPattern = #"^sk-[A-Za-z0-9_-]{20,}$"#
  private static let platformURL = URL(string: "https://platform.openai.com/")!
  private static let apiKeysURL = URL(string: "https://platform.openai.com/api-keys")!
  private static let quickstartURL = URL(string: "https://developers.openai.com/api/docs/quickstart")!
  private static let pricingURL = URL(string: "https://openai.com/api/pricing/")!

  @Bindable var appState: AppState
  /// Adds a header status pill (online bereit / OpenAI fehlt). On in the Modelle tab where the
  /// section is a standalone card; off in onboarding where the surrounding step shows status.
  var showsStatusPill: Bool = false

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
      HStack(spacing: 8) {
        SectionLabel(text: "OpenAI API Key", icon: "key.fill")
        if showsStatusPill {
          BlitzStatusPill(
            state: appState.hasOpenAIKey ? .online : .warning,
            label: appState.hasOpenAIKey ? "online bereit" : "OpenAI fehlt"
          )
        }
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
        setupHint
        keyEntryRow
        // spec #5: 'Speichern' anchored directly below the key entry row, before InfoDisclosure
        saveButton
      }

      // spec #2: full explanation moved into InfoDisclosure
      InfoDisclosure("wie bekomme ich einen key?") { apiKeyHelp }

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
    SecureField("sk-...", text: $apiKey)
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 11.5))
      .focused($focused, equals: .openAIAPIKey)
  }

  private var setupHint: some View {
    Text("ChatGPT Plus/Pro reicht hier nicht. Für Online-Transkription und Umschreiben brauchst du einen OpenAI Platform API-Key.")
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var apiKeyHelp: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        helpStep("1", "OpenAI Platform öffnen und anmelden.")
        helpStep("2", "Falls nötig Billing/Prepaid-Guthaben einrichten; die API wird separat von ChatGPT abgerechnet.")
        helpStep("3", "Auf der API-Key-Seite einen neuen Secret Key erstellen.")
        helpStep("4", "Key einmal kopieren, hier einfügen und speichern.")
      }

      Text("Der Key bleibt lokal im macOS Keychain. Bei Online-Modi sendet rede Audio/Text direkt an die OpenAI API.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      apiHelpLinks
    }
  }

  private func helpStep(_ number: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(number)
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .frame(width: 16, height: 16)
        .background(Circle().fill(RedeBrand.violet))
      Text(text)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var apiHelpLinks: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Link(destination: Self.platformURL) {
          Label("platform", systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))

        Link(destination: Self.apiKeysURL) {
          Label("api-key", systemImage: "key.fill")
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))
      }

      HStack(spacing: 8) {
        Link(destination: Self.quickstartURL) {
          Label("quickstart", systemImage: "book")
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))

        Link(destination: Self.pricingURL) {
          Label("preise", systemImage: "creditcard")
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))
      }
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
        } else {
          Text("speichern")
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
      guard trimmedAPIKey.range(of: Self.openAIAPIKeyPattern, options: .regularExpression) != nil
      else {
        errorText = "bitte trage einen plausiblen OpenAI API Key ein."
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
}
