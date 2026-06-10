import SwiftUI

/// Full transcription archive in its own resizable window. The 340pt popover only shows a
/// condensed preview (`ArchiveSettingsView`); this window groups the four facets — Diktate (stats),
/// Kontext (Office Memory), Verbesserungen (MEM-2) and Verlauf (the day-grouped entries) — behind a
/// native segmented control instead of one long scroll, so each reads on its own. Hosted by
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

    var label: String {
      switch self {
      case .verlauf: return "verlauf"
      case .diktate: return "diktate"
      case .kontext: return "kontext"
      case .verbesserungen: return "verbesserungen"
      }
    }
  }

  @State private var facet: Facet = .verlauf

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 12) {
        header
        facetPicker
      }
      .padding(.horizontal, 16)

      // Full-width ScrollView so the cards' liquidGlassCard shadow has room and is NOT clipped at
      // the sides. The inner horizontal padding (16) keeps the cards aligned with the header above.
      ScrollView {
        selectedFacet
          .padding(.top, 2)
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    // Top inset clears the floating traffic lights (full-size-content title bar).
    .padding(.top, 38)
    .frame(minWidth: 460, minHeight: 480)
    // rede voice: SF Rounded for the whole window, matching the popover/onboarding roots.
    .fontDesign(.rounded)
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .top) {
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
      Spacer()
      // Only offer "Archiv löschen" on the Verlauf facet while archiving is on — elsewhere (or with
      // it off) there's nothing to clear, and hiding it keeps an empty window reading as "disabled".
      if appState.isArchiveEnabled, facet == .verlauf {
        clearArchiveButton
      }
    }
  }

  /// Honest subtitle: confirms the local-only storage when on, but says plainly that archiving is
  /// off (and where to turn it on) so the empty facets below don't look like a bug.
  private var headerSubtitle: String {
    appState.isArchiveEnabled
      ? "lokal gespeichert (nur du, kein audio). nichts verlässt deinen Mac."
      : "archivierung ist aus — hier erscheint nichts, bis du sie im einstellungen-tab archiv aktivierst."
  }

  // MARK: - Facet picker + content

  private var facetPicker: some View {
    Picker("", selection: $facet) {
      ForEach(Facet.allCases) { facet in
        Text(facetLabel(facet)).tag(facet)
      }
    }
    .pickerStyle(.segmented)
    .controlSize(.small)
    .labelsHidden()
    .accessibilityLabel("Archiv-Ansicht")
  }

  /// Appends the pending MEM-2b suggestion count to the Verbesserungen segment so an actionable
  /// "Vorschlag" is visible without first opening that tab.
  private func facetLabel(_ facet: Facet) -> String {
    if facet == .verbesserungen {
      let count = appState.improvementSuggestions.count
      if count > 0 { return "\(facet.label) (\(count))" }
    }
    return facet.label
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
        facetOffHint(
          "verbesserungs-erkennung ist aus. aktiviere sie im tab vokabular (memory), "
            + "um zu sehen, wie du eingefügten text danach korrigierst.")
      }
    }
  }

  /// Quiet placeholder shown when an opt-in facet is turned off, so the segment reads as "disabled"
  /// rather than empty/broken.
  private func facetOffHint(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
  }

  // MARK: - List

  @ViewBuilder
  private var archiveList: some View {
    let grouped = appState.archiveStore.entriesByDay()

    if grouped.isEmpty {
      facetOffHint("noch keine einträge. neue transkriptionen erscheinen hier nach tag.")
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
