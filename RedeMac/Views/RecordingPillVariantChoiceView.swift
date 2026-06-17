import SwiftUI

extension RecordingPillView {
  var variantChoiceContent: some View {
    let variants = pendingVariants?.variants ?? []

    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "square.split.2x1")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(accentColor)
        Text("version wählen")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.primary)
        Text("einfügen oder kopieren")
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        CopyOnlyDismissButton(action: onDismiss)
      }
      .padding(.horizontal, 12)
      .padding(.top, 11)
      .padding(.bottom, 8)

      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(height: 0.5)

      HStack(alignment: .top, spacing: 10) {
        ForEach(Array(variants.enumerated()), id: \.element.id) { item in
          variantCard(item.element, index: item.offset)
        }
      }
      .padding(12)
    }
    .frame(width: 620)
    .modifier(CardGlassSurface())
  }

  private func variantCard(_ variant: RewriteVariant, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 7) {
        Text("\(index + 1)")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(accentColor)
          .frame(width: 18, height: 18)
          .background(accentColor.opacity(0.12), in: Circle())
        Text(variant.title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)
        Spacer(minLength: 0)
      }

      ScrollView(.vertical, showsIndicators: false) {
        Text(variant.text)
          .font(.system(size: 12))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .lineSpacing(3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.trailing, 4)
      }
      .frame(minHeight: 180, maxHeight: 220)

      HStack(spacing: 8) {
        Button {
          onChooseVariant(variant.id)
        } label: {
          Label("einfügen", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(VariantActionButtonStyle(role: .primary, accentColor: accentColor))
        .help("version an der ursprünglichen cursor-position einfügen")

        Button {
          onCopyVariant(variant.id)
        } label: {
          Label("kopieren", systemImage: "doc.on.doc")
        }
        .buttonStyle(VariantActionButtonStyle(role: .secondary, accentColor: accentColor))
        .help("version in die zwischenablage kopieren")

        Spacer(minLength: 0)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
    )
  }
}

private enum VariantActionButtonRole {
  case primary
  case secondary
}

private struct VariantActionButtonStyle: ButtonStyle {
  let role: VariantActionButtonRole
  let accentColor: Color

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .labelStyle(.titleAndIcon)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(foregroundColor)
      .padding(.horizontal, role == .primary ? 12 : 10)
      .padding(.vertical, 6)
      .background(backgroundShape)
      .opacity(configuration.isPressed ? 0.72 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }

  private var foregroundColor: Color {
    switch role {
    case .primary: return .white
    case .secondary: return accentColor
    }
  }

  private var backgroundShape: some View {
    Capsule(style: .continuous)
      .fill(role == .primary ? accentColor : accentColor.opacity(0.12))
  }
}
