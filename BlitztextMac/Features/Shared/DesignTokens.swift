import SwiftUI

// MARK: - Content-surface tokens (flat, no glass)
//
// THE surface language for content INSIDE cards, sections, tabs and windows:
//   .tokenCard(cornerRadius:)      — neutral list rows, tiles, status chips' parent rows
//   .tintBanner(_:cornerRadius:)   — accent-tinted guidance/warning banners and highlight rows
//
// Liquid Glass is reserved for floating chrome whose DIRECT parent is a floating backdrop
// (popover surface, recording pill, onboarding window) — see DESIGN.md "Flächen-Hierarchie".
// Everything nested inside a section card uses these flat MenuBarTokens surfaces on ALL macOS
// versions, which kills glass-on-glass stacking and keeps text legible.

private struct TokenCardModifier: ViewModifier {
  var cornerRadius: CGFloat
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(MenuBarTokens.cardFill(colorScheme: colorScheme))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(MenuBarTokens.cardStroke(colorScheme: colorScheme), lineWidth: 0.5)
      )
  }
}

private struct TintBannerModifier: ViewModifier {
  var accent: Color
  var cornerRadius: CGFloat
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(MenuBarTokens.tintFill(accent, colorScheme: colorScheme))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(MenuBarTokens.tintStroke(accent, colorScheme: colorScheme), lineWidth: 0.5)
      )
  }
}

extension View {
  /// Neutral flat row/tile surface (MenuBarTokens.cardFill + hairline). Radius 8 for list rows,
  /// 10 for stat tiles — per the DESIGN.md radius scale.
  func tokenCard(cornerRadius: CGFloat = 8) -> some View {
    modifier(TokenCardModifier(cornerRadius: cornerRadius))
  }

  /// Accent-tinted flat banner surface (MenuBarTokens.tintFill/tintStroke). The ONE look for
  /// guidance banners, warnings and highlight rows nested inside cards — identical on every
  /// macOS version, so captions stay legible.
  func tintBanner(_ accent: Color, cornerRadius: CGFloat = 10) -> some View {
    modifier(TintBannerModifier(accent: accent, cornerRadius: cornerRadius))
  }
}
