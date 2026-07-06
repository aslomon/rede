import SwiftUI

// MARK: - Recent dictations on the popover main page
//
// A calm, quieter-than-the-workflow-rows section under the workflow list. Renders NOTHING when
// there is no data, so the popover stays pixel-identical for fresh users. Rows sit on the flat
// `.tokenCard` surface (content language, not floating glass — see DESIGN.md Flächen-Hierarchie).
// Source of truth is `appState.recentDictations` (archive when enabled, RAM session buffer when
// not); this view never records, persists, or copies anything except via `ArchiveClipboard`.

struct RecentDictationsSection: View {
  let appState: AppState

  var body: some View {
    let recents = appState.recentDictations
    if recents.isEmpty {
      EmptyView()
    } else {
      content(recents)
    }
  }

  @ViewBuilder
  private func content(_ recents: [RecentDictation]) -> some View {
    VStack(spacing: 0) {
      Divider()
        .opacity(0.5)
        .padding(.horizontal, 16)
        .padding(.top, 8)

      header
        .padding(.horizontal, 16)
        .padding(.bottom, 4)

      VStack(spacing: 6) {
        ForEach(recents) { entry in
          RecentDictationRow(entry: entry, modeName: spokenModeName(for: entry))
        }
      }
      .padding(.horizontal, 16)

      if !appState.isArchiveEnabled {
        archiveOffCaption
          .padding(.horizontal, 16)
          .padding(.top, 6)
      }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack {
      SectionLabel(text: "letzte diktate", icon: "clock.arrow.circlepath")

      Spacer()

      if appState.isArchiveEnabled {
        if appState.archiveStore.entries.count > RecentDictationsBuffer.cap {
          Button("alle anzeigen") {
            NotificationCenter.default.post(name: .openArchiveWindow, object: nil)
          }
          .buttonStyle(PopoverActionButtonStyle(.quiet))
          .help("archiv-fenster öffnen")
        }
      } else {
        RedeStatusPill(state: .muted, label: "nur diese sitzung")
      }
    }
  }

  // MARK: Archive-off honesty caption

  private var archiveOffCaption: some View {
    HStack(spacing: 6) {
      Text("beim beenden weg.")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)

      Button("archiv aktivieren") {
        appState.openSettings(tab: 3)
      }
      .buttonStyle(PopoverActionButtonStyle(.quiet))

      Spacer(minLength: 0)
    }
  }

  private func spokenModeName(for entry: RecentDictation) -> String {
    let stored = entry.modeName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let stored, !stored.isEmpty { return stored }
    return appState.displayName(for: entry.mode)
  }
}

// MARK: - Single recent-dictation row

/// One recent dictation. The WHOLE row is a single `.plain` copy Button on a flat `.tokenCard`.
/// Hover brightens the fill one step and lifts the glyph to `.primary`; a copy shows the shared
/// `QuickCopyGlyph` checkmark and a green "kopiert" for 1.5 s, then re-arms on re-tap.
private struct RecentDictationRow: View {
  let entry: RecentDictation
  let modeName: String

  @Environment(\.colorScheme) private var colorScheme
  @State private var copied = false
  @State private var isHovered = false
  @State private var resetTask: Task<Void, Never>?

  var body: some View {
    Button {
      ArchiveClipboard.copyConcealed(entry.finalText)
      confirmCopy()
    } label: {
      HStack(spacing: 8) {
        Circle()
          .fill(entry.mode.accentColorValue)
          .frame(width: 6, height: 6)

        Text(entry.finalText)
          .font(.system(size: 11))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)

        Text(copied ? "kopiert" : RelativeTime.short(entry.date))
          .font(.system(size: 10))
          .foregroundStyle(
            copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
          )
          .fixedSize()

        QuickCopyGlyph(copied: copied)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(
            isHovered
              ? AnyShapeStyle(HierarchicalShapeStyle.primary)
              : AnyShapeStyle(HierarchicalShapeStyle.secondary))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(hoverTint)
      .tokenCard(cornerRadius: 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
    }
    .help(entry.finalText)
    .accessibilityLabel("diktat, \(modeName), \(RelativeTime.short(entry.date))")
    .accessibilityHint("kopiert den text in die zwischenablage")
  }

  /// Subtle one-step brighten on top of the token surface while hovered.
  private var hoverTint: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.06 : 0.04) : 0))
  }

  private func confirmCopy() {
    copied = true
    // Announce for VoiceOver — the visual swap alone is not audible (mirrors ArchiveQuickCopyButton).
    AccessibilityNotification.Announcement("kopiert").post()

    resetTask?.cancel()
    resetTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      guard !Task.isCancelled else { return }
      copied = false
    }
  }
}
