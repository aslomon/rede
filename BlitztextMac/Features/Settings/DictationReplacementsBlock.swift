import SwiftUI

/// Literal from→to replacements, rendered INLINE inside the "Begriffe" section (no own GroupBox, per
/// DESIGN.md de-nesting). "Say A → write B" rules run on-device, deterministically, on the cleaned
/// transcript before rewrite/paste. Replacements live next to Begriffe because they are the same
/// idea to the user: words the app should handle a specific way.
struct DictationReplacementsBlock: View {
  @Bindable var appState: AppState


  @State private var newFrom = ""
  @State private var newTo = ""
  @State private var newWholeWord = true
  @State private var showDuplicateHint = false

  private var replacements: [DictationReplacement] {
    appState.appSettings.dictationDictionary.replacements
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        Image(systemName: "arrow.left.arrow.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text("ersetzungen")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
      Text(
        "festes wortpaar: gesagt \u{2192} geschrieben. lokal angewendet, bevor der text eingefügt wird."
      )
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      replacementList
      addRow
      if showDuplicateHint { duplicateHint }
    }
  }

  // MARK: - Replacement list

  @ViewBuilder
  private var replacementList: some View {
    if !replacements.isEmpty {
      VStack(spacing: 5) {
        ForEach(replacements) { replacement in
          DictationReplacementRow(
            replacement: replacement,
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
      TextField("gesprochen", text: $newFrom)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
        .accessibilityLabel("Wort")
        .onSubmit { addReplacement() }
      Image(systemName: "arrow.right")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.tertiary)
      TextField("ersetzung", text: $newTo)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
        .accessibilityLabel("Ersetzung")
        .onSubmit { addReplacement() }

      Toggle("ganzes wort", isOn: $newWholeWord)
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .font(.system(size: 10.5))
        .accessibilityLabel("Nur ganzes Wort ersetzen")

      Button {
        addReplacement()
      } label: {
        Image(systemName: "plus.circle.fill")
      }
      .buttonStyle(PopoverIconButtonStyle(.primary))
      .accessibilityLabel("Ersetzung hinzufügen")
      .disabled(!canAdd)
    }
  }

  private var duplicateHint: some View {
    Text("schon vorhanden.")
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
