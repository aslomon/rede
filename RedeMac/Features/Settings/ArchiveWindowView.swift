import SwiftUI

/// Full transcription archive in its own resizable window. The 340pt popover only shows a
/// condensed preview (`ArchiveSettingsView`); this window groups the four facets — Diktate (stats),
/// Kontext (Office Memory), Verbesserungen (MEM-2) and Verlauf (the day-grouped entries) — behind a
/// RedeTabBar instead of one long scroll, so each reads on its own. Hosted by
/// `ArchiveWindowController`; reuses `ArchiveEntryRow` and the section views.
struct ArchiveWindowView: View {
  @Bindable var appState: AppState

  /// The four facets, in reading order. `Verlauf` (the actual archive entries) is the default —
  /// it's what the window's name promises.
  private enum Facet: String, CaseIterable, Identifiable {
    case verlauf
    case diktate
    case kontext
    case verbesserungen

    var id: String { rawValue }
  }

  @State private var facet: Facet = .verlauf

  var body: some View {
    // Same scaffold as LocalModelsView: one ScrollView, a leading VStack(spacing: 20), the header
    // as the first child, then the tab bar and the selected facet. Header + tab bar are grouped
    // tightly (spacing 12) so navigation stays anchored to the title. The clear action lives inside
    // the verlauf facet now, so the header is stable across all four facets.
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
          header
          facetPicker
        }
        selectedFacet
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      // Top inset clears the floating traffic lights (full-size-content title bar).
      .padding(.horizontal, 16)
      .padding(.top, 38)
      .padding(.bottom, 16)
    }
    .frame(minWidth: 540, minHeight: 580)
    // rede voice: SF Rounded for the whole window, matching the popover/onboarding roots.
    .fontDesign(.rounded)
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 8) {
        BrandMark(size: 18)
        Text("transkriptions-archiv")
          .font(.system(size: 16, weight: .semibold))
      }
      Text(headerSubtitle)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Honest subtitle: confirms the local-only storage when on, but says plainly that archiving is
  /// off (and where to turn it on) so the empty facets below don't look like a bug.
  private var headerSubtitle: String {
    appState.isArchiveEnabled
      ? "lokal gespeichert (nur du, kein audio). nichts verlässt deinen Mac."
      : "archivierung ist aus — hier erscheint nichts, bis du sie im einstellungen-tab archiv aktivierst."
  }

  // MARK: - Facet picker + content

  /// Icon+label pills (RedeTabBar); the verbesserungen tab carries a live count badge so an
  /// actionable "Vorschlag" is visible without first opening that facet.
  private var facetPicker: some View {
    RedeTabBar(
      selection: $facet,
      items: [
        RedeTabItem(tag: Facet.verlauf, label: "verlauf", icon: "clock.arrow.circlepath"),
        RedeTabItem(tag: Facet.diktate, label: "diktate", icon: "chart.bar"),
        RedeTabItem(tag: Facet.kontext, label: "kontext", icon: "scope"),
        RedeTabItem(
          tag: Facet.verbesserungen, label: "verbesserungen", icon: "wand.and.stars",
          badge: appState.improvementSuggestions.count),
      ]
    )
    .accessibilityLabel("Archiv-Ansicht")
  }

  @ViewBuilder
  private var selectedFacet: some View {
    switch facet {
    case .verlauf:
      archiveList
    case .diktate:
      DictationStatsSection(appState: appState)
    case .kontext:
      PasteContextSection(appState: appState)
    case .verbesserungen:
      if appState.isImprovementDetectionEnabled {
        ImprovementSection(appState: appState)
      } else {
        // Off-state guidance, not a bare text line: reads as a calm, disabled facet.
        EmptyStateCard(
          icon: "wand.and.stars",
          title: "verbesserungs-erkennung ist aus",
          caption:
            "aktiviere sie im tab vokabular (memory), um zu sehen, wie du eingefügten text danach "
            + "korrigierst.",
          accent: .secondary
        )
      }
    }
  }

  // MARK: - List

  @ViewBuilder
  private var archiveList: some View {
    let grouped = appState.archiveStore.entriesByDay()

    if grouped.isEmpty {
      EmptyStateCard(
        icon: "clock.arrow.circlepath",
        title: "noch keine einträge",
        caption: "neue transkriptionen erscheinen hier nach tag.",
        accent: .secondary
      )
    } else {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(grouped, id: \.day) { group in
          VStack(alignment: .leading, spacing: 6) {
            Text(dayHeader(for: group.day))
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)

            VStack(spacing: 6) {
              ForEach(group.entries) { entry in
                ArchiveEntryRow(
                  entry: entry,
                  appState: appState,
                  showActions: true,
                  onDelete: { appState.archiveStore.delete(entry.id) }
                )
              }
            }
          }
        }

        // Destructive clearing lives at the bottom of the list (right-aligned), not in the window
        // header — so switching facets no longer makes a header button appear/disappear.
        if appState.isArchiveEnabled {
          HStack {
            Spacer()
            clearArchiveButton
          }
          .padding(.top, 2)
        }
      }
    }
  }

  private var clearArchiveButton: some View {
    DestructiveClearButton(
      "archiv löschen",
      message:
        "alle archivierten transkriptionen werden on-device entfernt. das lässt sich nicht rückgängig machen."
    ) {
      appState.clearArchive()
    }
  }

  // MARK: - Helpers

  private func dayHeader(for day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "heute" }
    if calendar.isDateInYesterday(day) { return "gestern" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.dateFormat = "EEEE, d. MMMM"
    return formatter.string(from: day)
  }
}
