import SwiftUI

/// A single from→to replacement row in the Diktier-Wörterbuch. Shows the pair, a "Ganzes Wort"
/// toggle that exposes the behavior-changing `wholeWord` flag (whole-word vs substring matching),
/// and a remove button. Card fill/stroke route through `MenuBarTokens` so the row reads correctly
/// in both light and dark mode (DESIGN.md / colorScheme tokens).
struct DictationReplacementRow: View {
  let replacement: DictationReplacement
  let colorScheme: ColorScheme
  let onToggleWholeWord: (Bool) -> Void
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Text(replacement.from)
        .font(.system(size: 10.5, weight: .medium))
      Image(systemName: "arrow.right")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.tertiary)
      Text(replacement.to)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
      Spacer(minLength: 4)
      wholeWordToggle
      removeButton
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(MenuBarTokens.cardStroke(colorScheme: colorScheme), lineWidth: 0.5)
    )
  }

  private var wholeWordToggle: some View {
    Toggle(
      "Ganzes Wort",
      isOn: Binding(get: { replacement.wholeWord }, set: { onToggleWholeWord($0) })
    )
    .toggleStyle(.checkbox)
    .controlSize(.small)
    .font(.system(size: 10))
    .accessibilityLabel("Nur ganzes Wort ersetzen")
  }

  private var removeButton: some View {
    Button(action: onRemove) {
      Image(systemName: "xmark")
        .font(.system(size: 7, weight: .bold))
        .foregroundStyle(.tertiary)
    }
    .buttonStyle(SubtleButtonStyle())
    .accessibilityLabel("Ersetzung entfernen")
  }
}
