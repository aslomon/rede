import SwiftUI

/// "Diktier-Wörterbuch" section for the Modelle tab. Lets the user toggle spoken-punctuation
/// recognition and maintain a small list of literal from→to replacements that run on-device,
/// deterministically, on the cleaned transcript BEFORE the text is rewritten or pasted.
///
/// Mirrors the Eigennamen add/remove pattern and the DESIGN.md conventions (SettingsSection,
/// SubtleButtonStyle, 6pt fields, 10.5pt secondary captions, du-form). 340pt-friendly.
struct DictationDictionarySection: View {
  @Bindable var appState: AppState

  @Environment(\.colorScheme) private var colorScheme

  @State private var newFrom = ""
  @State private var newTo = ""
  @State private var newWholeWord = true
  @State private var showDuplicateHint = false

  private var replacements: [DictationReplacement] {
    appState.appSettings.dictationDictionary.replacements
  }

  private var spokenPunctuationEnabled: Bool {
    appState.appSettings.dictationDictionary.spokenPunctuationEnabled
  }

  var body: some View {
    SettingsSection(
      "Diktier-Wörterbuch",
      caption: "Ersetzt feste Wörter lokal, bevor der Text eingefügt wird."
    ) {
      punctuationToggle
      if spokenPunctuationEnabled {
        punctuationReference
        punctuationWarning
      }
      replacementList
      addRow
      if showDuplicateHint {
        duplicateHint
      }
    }
  }

  // MARK: - Spoken punctuation toggle + reference

  private var punctuationToggle: some View {
    Toggle(
      "Gesprochene Satzzeichen erkennen",
      isOn: $appState.appSettings.dictationDictionary.spokenPunctuationEnabled
    )
    .toggleStyle(.switch)
    .controlSize(.small)
    .font(.system(size: 11.5))
  }

  /// Compact, wrapping reference of the spoken→symbol mappings, read from the single source of
  /// truth (`DictationPostProcessor.punctuationReference`) so it can never drift from behavior.
  private var punctuationReference: some View {
    FlowLayout(spacing: 5) {
      ForEach(DictationPostProcessor.punctuationReference, id: \.spoken) { entry in
        mappingChip(spoken: entry.spoken, symbol: entry.symbol)
      }
    }
  }

  private func mappingChip(spoken: String, symbol: String) -> some View {
    HStack(spacing: 3) {
      Text(spoken)
        .font(.system(size: 10, weight: .medium))
      Text("→")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.tertiary)
      Text(symbol)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(
      Capsule().fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
    )
    .overlay(
      Capsule().strokeBorder(MenuBarTokens.cardStroke(colorScheme: colorScheme), lineWidth: 0.5)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(spoken) wird zu \(symbol)")
  }

  private var punctuationWarning: some View {
    Text("Achtung: gesprochene Wörter wie „Punkt“ oder „Komma“ werden dann zu Satzzeichen.")
      .font(.system(size: 10.5))
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Replacement list

  @ViewBuilder
  private var replacementList: some View {
    if replacements.isEmpty {
      Text("Noch keine Ersetzungen — füge unten ein Wortpaar hinzu.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(spacing: 5) {
        ForEach(replacements) { replacement in
          DictationReplacementRow(
            replacement: replacement,
            colorScheme: colorScheme,
            onToggleWholeWord: { setWholeWord(replacement, $0) },
            onRemove: { removeReplacement(replacement) }
          )
        }
      }
    }
  }

  // MARK: - Add row

  private var addRow: some View {
    HStack(spacing: 6) {
      TextField("Gesprochen", text: $newFrom)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
        .accessibilityLabel("Wort")
        .onSubmit { addReplacement() }
      Image(systemName: "arrow.right")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.tertiary)
      TextField("Ersetzung", text: $newTo)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
        .accessibilityLabel("Ersetzung")
        .onSubmit { addReplacement() }

      Toggle("Ganzes Wort", isOn: $newWholeWord)
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .font(.system(size: 10.5))
        .accessibilityLabel("Nur ganzes Wort ersetzen")

      Button {
        addReplacement()
      } label: {
        Image(systemName: "plus.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(.blue.opacity(0.7))
      }
      .buttonStyle(SubtleButtonStyle())
      .accessibilityLabel("Ersetzung hinzufügen")
      .disabled(!canAdd)
    }
  }

  private var duplicateHint: some View {
    Text("Schon vorhanden.")
      .font(.system(size: 10.5))
      .foregroundStyle(.orange)
      .transition(.opacity)
  }

  // MARK: - Mutations

  private var canAdd: Bool {
    !newFrom.trimmingCharacters(in: .whitespaces).isEmpty
      && !newTo.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func addReplacement() {
    let from = newFrom.trimmingCharacters(in: .whitespaces)
    let to = newTo.trimmingCharacters(in: .whitespaces)
    guard !from.isEmpty, !to.isEmpty else { return }
    guard
      !replacements.contains(where: { $0.from.caseInsensitiveCompare(from) == .orderedSame })
    else {
      flashDuplicateHint()
      return
    }
    withAnimation(.easeOut(duration: 0.15)) {
      appState.appSettings.dictationDictionary.replacements.append(
        DictationReplacement(from: from, to: to, wholeWord: newWholeWord))
    }
    newFrom = ""
    newTo = ""
    newWholeWord = true
  }

  private func flashDuplicateHint() {
    withAnimation(.easeOut(duration: 0.15)) { showDuplicateHint = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      withAnimation(.easeOut(duration: 0.2)) { showDuplicateHint = false }
    }
  }

  private func setWholeWord(_ replacement: DictationReplacement, _ value: Bool) {
    guard let index = replacements.firstIndex(where: { $0.id == replacement.id }) else { return }
    appState.appSettings.dictationDictionary.replacements[index].wholeWord = value
  }

  private func removeReplacement(_ replacement: DictationReplacement) {
    withAnimation(.easeOut(duration: 0.15)) {
      appState.appSettings.dictationDictionary.replacements.removeAll { $0.id == replacement.id }
    }
  }
}
