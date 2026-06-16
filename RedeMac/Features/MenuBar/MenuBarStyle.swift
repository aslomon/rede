import SwiftUI

// MARK: - rede brand palette (single source of truth)

/// The rede brand colors. `violet` is the primary brand accent (timeless, readable in both
/// schemes); `lime` is the high-energy "live" pop — only legible on dark/ink surfaces, so use it
/// for the recording state, the icon, and dark-context accents, never as text on a light fill.
/// See DESIGN.md (rede edition).
enum RedeBrand {
  static let violet = Color(red: 0.431, green: 0.337, blue: 0.973)  // #6E56F8
  static let lime = Color(red: 0.800, green: 1.000, blue: 0.102)  // #CCFF1A
  static let ink = Color(red: 0.055, green: 0.043, blue: 0.102)  // #0E0B1A

  /// The wordmark accent dot: lime on dark surfaces (where it pops), violet on light (where lime
  /// would wash out). Keeps the mark legible in both menu-bar appearances.
  static func dotColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? lime : violet
  }
}

// MARK: - Mode accent color (single source of truth)

extension WorkflowType {
  /// The mode accent as a SwiftUI Color (DESIGN.md per-mode palette).
  var accentColorValue: Color {
    switch self {
    case .transcription: return .blue
    case .localTranscription: return .green
    case .textImprover: return .purple
    case .dampfAblassen: return .orange
    case .emojiText: return .cyan
    }
  }
}

// MARK: - Color-scheme-aware surface tokens

/// Static helpers that produce fills / strokes that read correctly in both
/// light and dark mode. All opacities are chosen so the tinted fills have
/// at least 3:1 contrast against a `.controlBackgroundColor` surface.
enum MenuBarTokens {
  // MARK: Card fills

  /// Neutral card fill that adapts to colorScheme.
  /// Uses `windowBackgroundColor` at a fixed alpha so the card is always
  /// legible over the popover surface, instead of `primary.opacity` which
  /// collapses to near-invisible in dark-over-bright contexts.
  static func cardFill(colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color(nsColor: .windowBackgroundColor).opacity(0.55)
      : Color(nsColor: .controlBackgroundColor).opacity(0.80)
  }

  static func cardStroke(colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color(nsColor: .separatorColor).opacity(0.55)
      : Color(nsColor: .separatorColor).opacity(0.45)
  }

  // MARK: Accent tint fills (for banners and icon tiles)

  /// Tinted fill for accent-colored cards / icon tiles.
  static func tintFill(_ accent: Color, colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? accent.opacity(0.18)
      : accent.opacity(0.10)
  }

  /// Tinted stroke for accent-colored cards / icon tiles.
  static func tintStroke(_ accent: Color, colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? accent.opacity(0.30)
      : accent.opacity(0.18)
  }

  // MARK: Header band

  /// Transparent so the header sits on the popover's normal background (`.redeSurface`)
  /// instead of a distinct opaque band — it now reads as one continuous, popup-wide surface with
  /// the content. The root surface already provides the dark-mode backstop; the `Divider` below the
  /// header keeps the visual separation.
  static func headerBand(colorScheme _: ColorScheme) -> Color {
    .clear
  }

  // MARK: Keycap tokens (for HotkeyBadge)
  //
  // Centralises the 8 inline color literals that were previously scattered across
  // HotkeyBadge's four private computed vars. LiquidGlass.liquidGlassKeycap() uses
  // these on the macOS 14–25 fallback path.

  /// Keycap background fill — replaces `keyBackgroundColor` in HotkeyBadge.
  static func keycapFill(colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color.white.opacity(0.12)
      : Color.black.opacity(0.09)
  }

  /// Keycap border stroke — replaces `keyStrokeColor` in HotkeyBadge.
  static func keycapStroke(colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color.white.opacity(0.20)
      : Color.black.opacity(0.16)
  }

  /// Keycap label foreground — replaces `keyTextColor` in HotkeyBadge.
  static func keycapText(colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
      ? Color.white.opacity(0.84)
      : Color.black.opacity(0.72)
  }
}
