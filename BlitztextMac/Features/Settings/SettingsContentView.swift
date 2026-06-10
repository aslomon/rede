import AppKit
import SwiftUI

struct SettingsContentView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      // Four-tab segmented picker (short labels fit the 340pt popover).
      Picker("", selection: $appState.settingsTabSelection) {
        Text("Prompts").tag(0)
        Text("Modelle").tag(1)
        Text("Vokabular").tag(2)
        Text("Archiv").tag(3)
        Text("System").tag(4)
      }
      .pickerStyle(.segmented)
      .controlSize(.small)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

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
  /// always-visible segmented picker. The `setupNudgeBanner` shows on EVERY tab while unconfigured,
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
        Text("Richte rede ein")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.primary)
        Text(
          "Die geführte Einrichtung erledigt Rechte, Verarbeitung und Modi in wenigen Schritten."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      Button("Öffnen") {
        NotificationCenter.default.post(name: .openOnboardingWindow, object: nil)
      }
      .font(.system(size: 10.5, weight: .medium))
      .buttonStyle(PopoverActionButtonStyle(.primary))
    }
    .padding(10)
    .liquidGlassInfoBanner(accent: .blue, cornerRadius: 10)
  }
}

// MARK: - Section Label (quiet style)

struct SectionLabel: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
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
