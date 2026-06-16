import SwiftUI

// MARK: - rede tab bar (icon + label pills)
//
// THE navigation control between destinations (settings tabs, archive facets). Horizontal pills:
// concept icon next to a lowercase label, the active tab as a solid brand-violet capsule with white
// text. Value choices stay native segmented pickers (text-only) — see DESIGN.md
// "segmented = wertauswahl, RedeTabBar = navigation".
//
// Known trade-off vs. the native segmented control: no arrow-key cycling; the items are regular
// buttons (Full Keyboard Access reachable) carrying .isSelected traits.

struct RedeTabItem<Tag: Hashable>: Identifiable {
  let tag: Tag
  let label: String
  let icon: String
  /// Small violet count badge over the item (e.g. pending suggestions). nil or 0 = hidden.
  var badge: Int? = nil

  var id: Tag { tag }
}

struct RedeTabBar<Tag: Hashable>: View {
  @Binding var selection: Tag
  let items: [RedeTabItem<Tag>]

  @Environment(\.colorScheme) private var colorScheme
  @State private var hoveredTag: Tag?

  var body: some View {
    HStack(spacing: 2) {
      ForEach(items) { item in
        tabButton(item)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func tabButton(_ item: RedeTabItem<Tag>) -> some View {
    let isActive = item.tag == selection
    return Button {
      withAnimation(.easeInOut(duration: 0.15)) { selection = item.tag }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: item.icon)
          .font(.system(size: 11, weight: .semibold))
        Text(item.label)
          .font(.system(size: 10, weight: isActive ? .semibold : .medium))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(inactiveForeground))
      .padding(.horizontal, 4)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, minHeight: 28)
      .background(pillBackground(isActive: isActive, isHovered: hoveredTag == item.tag))
      .overlay(alignment: .topTrailing) { badgeView(item.badge) }
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      hoveredTag = hovering ? item.tag : (hoveredTag == item.tag ? nil : hoveredTag)
    }
    .accessibilityLabel(accessibilityLabel(for: item))
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }

  @ViewBuilder
  private func pillBackground(isActive: Bool, isHovered: Bool) -> some View {
    if isActive {
      Capsule(style: .continuous)
        .fill(RedeBrand.violet)
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: 0.5)
        )
    } else if isHovered {
      Capsule(style: .continuous)
        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
    }
  }

  private var inactiveForeground: Color {
    colorScheme == .dark ? Color.white.opacity(0.78) : Color.black.opacity(0.68)
  }

  @ViewBuilder
  private func badgeView(_ count: Int?) -> some View {
    if let count, count > 0 {
      Text("\(count)")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 3.5)
        .padding(.vertical, 1)
        .background(Capsule(style: .continuous).fill(RedeBrand.violet))
        .offset(x: 2, y: -4)
        .accessibilityHidden(true)
    }
  }

  private func accessibilityLabel(for item: RedeTabItem<Tag>) -> String {
    if let count = item.badge, count > 0 {
      return "\(item.label), \(count) " + (count == 1 ? "Vorschlag" : "Vorschläge")
    }
    return item.label
  }
}
