import SwiftUI

extension RecordingPillView {
  var variantChoiceContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "square.split.2x1")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(accentColor)
        Text("version wählen")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        CopyOnlyDismissButton(action: onDismiss)
      }
      .padding(.horizontal, 12)
      .padding(.top, 11)
      .padding(.bottom, 8)

      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(height: 0.5)

      VStack(spacing: 8) {
        ForEach(pendingVariants?.variants ?? []) { variant in
          variantCard(variant)
        }
      }
      .padding(10)
    }
    .frame(width: 380)
    .modifier(CardGlassSurface())
  }

  private func variantCard(_ variant: RewriteVariant) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(variant.title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      ScrollView(.vertical, showsIndicators: false) {
        Text(variant.text)
          .font(.system(size: 11.5))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .lineSpacing(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 94)

      HStack(spacing: 8) {
        Button {
          onChooseVariant(variant.id)
        } label: {
          Text("einfügen")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(accentColor, in: Capsule())
        }
        .buttonStyle(.plain)

        Button {
          onCopyVariant(variant.id)
        } label: {
          Text("kopieren")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)

        Spacer(minLength: 0)
      }
    }
    .padding(9)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.035))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
    )
  }
}
