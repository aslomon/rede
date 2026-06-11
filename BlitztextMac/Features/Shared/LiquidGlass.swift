import SwiftUI

// MARK: - Liquid Glass (single source of truth)
//
// ALL @available(macOS 26.0, *) gating lives here. Views call named wrappers only —
// no direct .glassEffect, GlassEffectContainer, or if #available at call sites.
//
// Verified API signatures (macOS 26 SDK / WWDC 2025):
//   .glassEffect(_ glass: Glass = .regular, in shape: some Shape = .rect, isEnabled: Bool = true)
//   Glass modifiers: .tint(_:)  .interactive()   variants: .regular  .clear  .identity
//   GlassEffectContainer(spacing:) { content }  — spacing is a CGFloat, content is a ViewBuilder
//   .glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View
//   .buttonStyle(.glass)          — type: GlassButtonStyle
//   .buttonStyle(.glassProminent) — type: GlassProminentButtonStyle

// MARK: - Shared tokens & constants

public enum LiquidGlass {
  /// Shared width for all expanded pill card states (copy-only and variant choice).
  public static let pillExpandedWidth: CGFloat = 340
  /// Standard corner radius for popover cards, banners, and OnboardingCard.
  public static let cardCornerRadius: CGFloat = 10
  /// Corner radius for expanded pill cards (CardGlassModifier).
  public static let pillCardRadius: CGFloat = 14
  /// Tint strength for accent-tinted glass on macOS 26. Full-strength accent glass produced
  /// saturated surfaces on which `.secondary` captions became hard to read (legibility bug);
  /// a soft wash keeps the accent identity while text stays on a near-neutral surface.
  public static let tintedGlassOpacity: CGFloat = 0.35
}

// MARK: - Pill (capsule) glass

/// Applies the recording pill's background surface.
/// macOS 26+: native Liquid Glass capsule.
/// macOS 14–25: .regularMaterial capsule + shadow.
public struct PillGlassModifier: ViewModifier {
  var accent: Color?

  public init(accent: Color? = nil) {
    self.accent = accent
  }

  public func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(accent.map { .regular.tint($0) } ?? .regular, in: .capsule)
        // Shadow on macOS 26 path (glass itself provides separation but still needs y lift)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    } else {
      content
        .background(Capsule(style: .continuous).fill(.regularMaterial))
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
  }
}

// MARK: - Card (rounded-rect) glass

/// Applies a rounded-rect glass surface for expanded pill cards.
/// macOS 26+: native Liquid Glass (radius 14) + shadow.
/// macOS 14–25: regularMaterial + stroke border + shadow.
public struct CardGlassModifier: ViewModifier {
  private let radius: CGFloat = LiquidGlass.pillCardRadius

  public init() {}

  public func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(.regular, in: .rect(cornerRadius: radius))
        // Shadow on macOS 26 path
        .shadow(color: .black.opacity(0.15), radius: 20, y: 5)
    } else {
      content
        .background(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
    }
  }
}

// MARK: - Popover surface backstop

/// Opaque backstop for the entire popover content area (window back-plane).
/// macOS 26+: .glassEffect on .rect (the real design).
/// macOS 14–25: .regularMaterial + windowBackgroundColor underlay.
public struct BlitztextSurface: ViewModifier {
  public init() {}

  public func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(.regular, in: .rect)
    } else {
      content
        .background(.regularMaterial)
        .background(Color(nsColor: .windowBackgroundColor))
    }
  }
}

// MARK: - Card-level fallback (macOS 14–25, internal)

/// Used by liquidGlassCard and liquidGlassTintedCard on macOS 14–25.
private struct LiquidGlassCardFallback: ViewModifier {
  var accent: Color?
  var cornerRadius: CGFloat
  @Environment(\.colorScheme) private var colorScheme

  private var fill: Color {
    if let accent {
      return MenuBarTokens.tintFill(accent, colorScheme: colorScheme)
    }
    return MenuBarTokens.cardFill(colorScheme: colorScheme)
  }

  private var stroke: Color {
    if let accent {
      return MenuBarTokens.tintStroke(accent, colorScheme: colorScheme)
    }
    return MenuBarTokens.cardStroke(colorScheme: colorScheme)
  }

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(fill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(stroke, lineWidth: 0.5)
      )
  }
}

// MARK: - Chip background (macOS 26: thinMaterial; macOS 14–25: MenuBarTokens fill)
//
// Used for RecognizeChip / punctuationMappingChip inside GroupBox.
// Per no-stacking rule: .thinMaterial (not .glassEffect) inside GroupBox on macOS 26.

public struct ChipBackgroundModifier: ViewModifier {
  var accent: Color
  @Environment(\.colorScheme) private var colorScheme

  public init(accent: Color) {
    self.accent = accent
  }

  public func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      // thinMaterial inside GroupBox — no .glassEffect to avoid stacking
      content
        .background(.thinMaterial, in: Capsule(style: .continuous))
    } else {
      content
        .background(
          Capsule(style: .continuous)
            .fill(MenuBarTokens.tintFill(accent, colorScheme: colorScheme))
        )
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(
              MenuBarTokens.tintStroke(accent, colorScheme: colorScheme), lineWidth: 0.5)
        )
    }
  }
}

// MARK: - GlassEffectContainerView
//
// Wraps content in GlassEffectContainer(spacing:) on macOS 26+.
// Falls back to a plain VStack or HStack on macOS 14–25.

public struct GlassEffectContainerView<Content: View>: View {
  var spacing: CGFloat
  var axis: Axis
  @ViewBuilder var content: Content

  public init(
    spacing: CGFloat = 0,
    axis: Axis = .vertical,
    @ViewBuilder content: () -> Content
  ) {
    self.spacing = spacing
    self.axis = axis
    self.content = content()
  }

  public var body: some View {
    if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) {
        content
      }
    } else {
      fallbackStack
    }
  }

  @ViewBuilder
  private var fallbackStack: some View {
    switch axis {
    case .horizontal:
      HStack(spacing: spacing) { content }
    case .vertical:
      VStack(spacing: spacing) { content }
    }
  }
}

// MARK: - GlassActionButtonStyle
//
// For secondary floating action buttons (pill affordance buttons, onboarding chrome).
// macOS 26+: glass visual using .glassEffect(.regular.interactive()) on the label.
//   .buttonStyle(.glass) cannot be applied inside makeBody (applies to Button, not View);
//   applying .glassEffect directly on the label replicates the .glass button appearance.
// macOS 14–25: PopoverActionButtonStyle(.primary) fallback.

public struct GlassActionButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    if #available(macOS 26.0, *) {
      configuration.label
        // Same type as PopoverActionButtonStyle so button text is ONE size on every OS path.
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
        // Disabled buttons must read as disabled on the glass path too (the 14–25
        // fallback gets this from PopoverActionButtonStyle).
        .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    } else {
      PopoverActionButtonStyle(.primary).makeBody(configuration: configuration)
    }
  }
}

// MARK: - GlassProminentButtonStyle
//
// For the primary CTA in floating surfaces (Einfügen, Fertig in pill/onboarding).
// macOS 26+: prominent glass using .glassEffect(.regular.tint(.accentColor).interactive()).
//   Same reasoning as GlassActionButtonStyle — applies glassEffect to the label view directly.
// macOS 14–25: PopoverActionButtonStyle(.primary) fallback.

public struct GlassProminentButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    if #available(macOS 26.0, *) {
      configuration.label
        // Same type as PopoverActionButtonStyle so button text is ONE size on every OS path.
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(Color.accentColor).interactive(), in: .rect(cornerRadius: 8))
        // Disabled buttons must read as disabled on the glass path too (the 14–25
        // fallback gets this from PopoverActionButtonStyle).
        .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    } else {
      PopoverActionButtonStyle(.primary).makeBody(configuration: configuration)
    }
  }
}

// MARK: - Public View extensions

extension View {
  /// Applies the popover's opaque surface backstop.
  public func blitztextSurface() -> some View {
    modifier(BlitztextSurface())
  }

  /// A card-shaped glass surface with an optional accent tint.
  /// - macOS 26+: .glassEffect with a SOFT accent wash (tintedGlassOpacity) + shadow — full
  ///   accent tint made secondary text illegible on the saturated glass.
  /// - macOS 14–25: MenuBarTokens fill + hairline border
  @ViewBuilder
  public func liquidGlassCard(
    accent: Color? = nil, cornerRadius: CGFloat = LiquidGlass.cardCornerRadius
  ) -> some View {
    if #available(macOS 26.0, *) {
      self
        .glassEffect(
          accent.map { .regular.tint($0.opacity(LiquidGlass.tintedGlassOpacity)) } ?? .regular,
          in: .rect(cornerRadius: cornerRadius)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 3)
    } else {
      modifier(LiquidGlassCardFallback(accent: accent, cornerRadius: cornerRadius))
    }
  }

  /// A capsule-shaped glass surface with an optional accent tint (wraps PillGlassModifier).
  public func liquidGlassCapsule(accent: Color? = nil) -> some View {
    modifier(PillGlassModifier(accent: accent))
  }

  /// A tinted card-shaped glass surface for accent-colored banners and cards.
  /// - macOS 26+: .glassEffect with a SOFT accent wash (tintedGlassOpacity) — full accent tint
  ///   made `.secondary` banner copy illegible on the saturated glass.
  /// - macOS 14–25: MenuBarTokens.tintFill fill + tintStroke hairline border
  @ViewBuilder
  public func liquidGlassTintedCard(
    accent: Color, cornerRadius: CGFloat = LiquidGlass.cardCornerRadius
  ) -> some View {
    if #available(macOS 26.0, *) {
      self
        .glassEffect(
          .regular.tint(accent.opacity(LiquidGlass.tintedGlassOpacity)),
          in: .rect(cornerRadius: cornerRadius)
        )
    } else {
      modifier(LiquidGlassCardFallback(accent: accent, cornerRadius: cornerRadius))
    }
  }

  /// Semantic alias for .liquidGlassTintedCard — use for info/warning banner contexts.
  /// - macOS 26+: .glassEffect(.regular.tint(accent), in: .rect(cornerRadius:))
  /// - macOS 14–25: MenuBarTokens.tintFill fill + tintStroke hairline border
  public func liquidGlassInfoBanner(
    accent: Color, cornerRadius: CGFloat = LiquidGlass.cardCornerRadius
  ) -> some View {
    liquidGlassTintedCard(accent: accent, cornerRadius: cornerRadius)
  }

  /// For HotkeyBadge keycap tokens.
  /// - macOS 26+: .glassEffect(.clear, in: .rect(cornerRadius: 6))
  /// - macOS 14–25: MenuBarTokens.keycapFill/keycapStroke RoundedRectangle
  @ViewBuilder
  public func liquidGlassKeycap() -> some View {
    if #available(macOS 26.0, *) {
      self
        .glassEffect(.clear, in: .rect(cornerRadius: 6))
    } else {
      modifier(KeycapFallbackModifier())
    }
  }

  /// Hover row background with glassEffectID morphing between adjacent rows.
  /// - macOS 26+: .glassEffect(.interactive, ...) + .glassEffectID when hovered; .clear otherwise
  /// - macOS 14–25: tintFill RoundedRectangle when hovered; .clear otherwise
  ///
  /// Requires a @Namespace scoped to the parent list view so morphing works across adjacent rows.
  public func glassRowBackground(
    id _: AnyHashable,
    namespace _: Namespace.ID,
    isHovered: Bool,
    accentColor: Color
  ) -> some View {
    // Calm, static hover highlight on ALL macOS versions. The macOS 26 interactive Liquid
    // Glass morph (.glassEffect(.interactive) + .glassEffectID) read as a gimmicky warping
    // blob that chased the cursor and morphed between rows on a dense utility list, and it
    // stacked glass-on-glass inside the already-glassy popover (against DESIGN.md). A subtle
    // accent tint is the restrained, native row highlight we want. id/namespace stay in the
    // signature for call-site stability.
    modifier(RowBackgroundFallback(isHovered: isHovered, accentColor: accentColor))
  }
}

// MARK: - Keycap fallback (macOS 14–25, internal)

private struct KeycapFallbackModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(MenuBarTokens.keycapFill(colorScheme: colorScheme))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(MenuBarTokens.keycapStroke(colorScheme: colorScheme), lineWidth: 0.8)
      )
  }
}

// MARK: - Row background fallback (macOS 14–25, internal)

private struct RowBackgroundFallback: ViewModifier {
  var isHovered: Bool
  var accentColor: Color
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            isHovered
              ? MenuBarTokens.tintFill(accentColor, colorScheme: colorScheme)
              : Color.clear
          )
      )
  }
}
