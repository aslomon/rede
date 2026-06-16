import SwiftUI

/// A single from→to replacement row in the Diktier-Wörterbuch. Shows the pair, a small
/// `textformat.abc` icon that indicates the `wholeWord` flag (tapping it toggles), and a
/// remove button. The inline Toggle checkbox is replaced by the icon indicator — less visual
/// weight per row while keeping the affordance accessible. Card fill/stroke route through
/// `MenuBarTokens` so the row reads correctly in both light and dark mode.
struct DictationReplacementRow: View {
  let replacement: DictationReplacement
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
      wholeWordIndicator
      removeButton
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .tokenCard(cornerRadius: 6)
  }

  /// `textformat.abc` icon at 9pt. `.tertiary` foreground when `wholeWord` is false (substring
  /// matching), `.primary` when true (whole-word matching). Tapping toggles the flag without
  /// the bulk of a checkbox Toggle per row.
  private var wholeWordIndicator: some View {
    Button {
      onToggleWholeWord(!replacement.wholeWord)
    } label: {
      Image(systemName: "textformat.abc")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(replacement.wholeWord ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
    }
    .buttonStyle(.plain)
    .contentShape(Circle().scale(1.6))
    .help(
      replacement.wholeWord
        ? "nur ganzes wort ersetzen (aktiv) — tippen zum deaktivieren"
        : "auch als teilwort ersetzen — tippen für ganzes-wort-modus"
    )
    .accessibilityLabel("Nur ganzes Wort ersetzen")
    .accessibilityValue(replacement.wholeWord ? "aktiv" : "inaktiv")
  }

  private var removeButton: some View {
    Button(action: onRemove) {
      Image(systemName: "xmark")
        .font(.system(size: 7, weight: .bold))
        .foregroundStyle(.tertiary)
    }
    .buttonStyle(.plain)
    .contentShape(Circle().scale(1.6))
    .accessibilityLabel("Ersetzung entfernen")
  }
}
