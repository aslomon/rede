import AppKit
import SwiftUI

struct SettingsContentView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      // Five destination tabs as icon+label pills (RedeTabBar — DESIGN.md tab pattern).
      RedeTabBar(
        selection: $appState.settingsTabSelection,
        items: [
          RedeTabItem(tag: 0, label: "prompts", icon: "rectangle.stack"),
          RedeTabItem(tag: 1, label: "modelle", icon: "shippingbox"),
          RedeTabItem(tag: 2, label: "vokabular", icon: "character.book.closed"),
          RedeTabItem(tag: 3, label: "archiv", icon: "archivebox"),
          RedeTabItem(tag: 4, label: "system", icon: "gearshape"),
        ]
      )
      .padding(.horizontal, 12)
      .padding(.top, 10)
      .padding(.bottom, 6)

      ScrollView {
        VStack(spacing: 0) {
          switch appState.settingsTabSelection {
          case 0:
            // Setup nudge is only shown on the Prompts tab (DESIGN.md: setupNudgeBanner tab 0 only)
            if !appState.isConfigured {
              setupNudgeBanner
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            PromptsSettingsView(appState: appState, selectTab: selectTab)
          case 1:
            ModelsSettingsView(appState: appState, selectTab: selectTab)
          case 2:
            VocabularySettingsView(appState: appState)
          case 3:
            ArchiveSettingsView(appState: appState)
          default:
            SystemSettingsView(appState: appState)
          }
        }
      }
    }
    .onAppear {
      appState.refreshAccessibilityPermission()
      if !(0...4).contains(appState.settingsTabSelection) {
        appState.settingsTabSelection = defaultTabSelection
      }
    }
  }

  /// Programmatic tab switch handed to child tabs so their empty-state CTAs can jump the user to
  /// the tab that unblocks a feature (e.g. "Zu Modelle" from the Prompts tab).
  private func selectTab(_ index: Int) {
    appState.settingsTabSelection = index
  }

  /// Always land on Prompts (tab 0), the primary tab — the other three are one tap away in the
  /// always-visible tab bar. The `setupNudgeBanner` shows on EVERY tab while unconfigured,
  /// so guidance no longer needs to hijack the landing tab to System (which hid the other tabs).
  private var defaultTabSelection: Int { 0 }

  /// Empty-state nudge: while rede is unconfigured, point the user at the guided wizard.
  private var setupNudgeBanner: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "sparkles")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.blue)
        .frame(width: 18, height: 18)

      VStack(alignment: .leading, spacing: 3) {
        Text("richte rede ein")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)
        Text(
          "die geführte einrichtung erledigt rechte, verarbeitung und modi in wenigen schritten."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      Button("öffnen") {
        NotificationCenter.default.post(name: .openOnboardingWindow, object: nil)
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
    }
    .padding(10)
    .liquidGlassInfoBanner(accent: .blue, cornerRadius: 10)
  }
}

// MARK: - Section Label (quiet style)

/// The app-wide section heading: optional concept icon + uppercase label. The icon comes from the
/// rede icon language (one SF Symbol per concept, DESIGN.md) and stays quiet — same secondary
/// colour and near-text size as the label itself.
struct SectionLabel: View {
  let text: String
  var icon: String? = nil

  var body: some View {
    HStack(spacing: 5) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      Text(text.uppercased())
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }
}
// MARK: - Flow Layout (for term tags)

struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = arrangeSubviews(proposal: proposal, subviews: subviews)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = arrangeSubviews(proposal: proposal, subviews: subviews)
    for (index, position) in result.positions.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
        proposal: .unspecified)
    }
  }

  private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (
    positions: [CGPoint], size: CGSize
  ) {
    let maxWidth = proposal.width ?? .infinity
    var positions: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth && x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      positions.append(CGPoint(x: x, y: y))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      maxX = max(maxX, x)
    }

    return (positions, CGSize(width: maxX, height: y + rowHeight))
  }
}
