import SwiftUI

/// Shared visual helpers for the wizard steps so each step file stays small and consistent with
/// DESIGN.md. The step title/subtitle live in the wizard's centered hero header — steps render
/// only their controls, usually grouped in `OnboardingCard`s.
enum OnboardingChrome {
  static let cardCornerRadius: CGFloat = 10
  static let contentSpacing: CGFloat = 14
}

/// A neutral surface card: 12pt padding, faint fill, hairline border. Used by most step bodies.
/// macOS 26+: Liquid Glass card via `.liquidGlassCard(accent:cornerRadius:)`.
/// macOS 14–25: MenuBarTokens fill + hairline strokeBorder.
struct OnboardingCard<Content: View>: View {
  var accent: Color?
  @ViewBuilder var content: Content

  init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
    self.accent = accent
    self.content = content()
  }

  var body: some View {
    content
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .liquidGlassCard(accent: accent, cornerRadius: OnboardingChrome.cardCornerRadius)
  }
}

/// A single labelled value row used by the recap list, with a green check or grey dash badge.
struct OnboardingRecapRow: View {
  let title: String
  let detail: String
  let isPositive: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: isPositive ? "checkmark.circle.fill" : "minus.circle")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isPositive ? Color.green : Color.secondary)
        .frame(width: 18, height: 18)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.primary)
        Text(detail)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    // VoiceOver reads icon + title + detail in one pass.
    .accessibilityElement(children: .combine)
  }
}
