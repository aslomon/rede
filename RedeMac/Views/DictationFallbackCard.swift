import SwiftUI

/// Readable recovery surface for output that could not be inserted automatically.
struct DictationFallbackCard: View {
  let text: String
  let onCopy: (String) -> Void
  let onDismiss: () -> Void

  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      preview
      footer
    }
    .padding(14)
    .frame(width: LiquidGlass.pillExpandedWidth)
    .fontDesign(.rounded)
    .task(id: copied) {
      guard copied else { return }
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      copied = false
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "doc.on.clipboard")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(RedeBrand.violet)
        .frame(width: 32, height: 32)
        .background(RedeBrand.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 3) {
        Text("dein text liegt bereit.")
          .font(.system(size: 13, weight: .semibold))
        Text("automatisch einfügen ging hier nicht.")
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      CopyOnlyDismissButton(action: onDismiss)
    }
  }

  private var preview: some View {
    ScrollView(.vertical) {
      Text(text)
        .font(.system(size: 12))
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
    }
    .frame(height: 136)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
    }
  }

  private var footer: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("mit ⌘V einfügen")
          .font(.system(size: 11, weight: .semibold))
        Text("schon in der zwischenablage")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Button {
        onCopy(text)
        copied = true
        AccessibilityNotification.Announcement("kopiert").post()
      } label: {
        HStack(spacing: 5) {
          QuickCopyGlyph(copied: copied)
          Text(copied ? "kopiert" : "kopieren")
        }
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
      .accessibilityLabel("Text erneut kopieren")
      .help("text erneut in die zwischenablage kopieren")
    }
  }
}
