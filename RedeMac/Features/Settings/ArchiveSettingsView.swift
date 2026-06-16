import SwiftUI

// MARK: - Archive + Memory settings (Tab 2: Archiv)

/// Phase 4 UI: the opt-in transcription archive (text only) plus the two-speed Memory
/// curation surface. Everything here is privacy-first — opt-in, default OFF, on-device,
/// purgeable. The services layer (AppState) does the work; this view only presents it.
struct ArchiveSettingsView: View {
  @Bindable var appState: AppState

  @State private var showClearArchiveConfirm = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      archiveSection
    }
    .padding(16)
  }

  // MARK: - Archive

  /// Header pill mirrors the archive state at a glance: muted "aus", or the live entry count.
  private var archivePill: BlitzStatusPill {
    guard appState.isArchiveEnabled else {
      return BlitzStatusPill(state: .muted, label: "aus")
    }
    let count = appState.archiveStore.entries.count
    if count == 0 { return BlitzStatusPill(state: .ready, label: "aktiv") }
    return BlitzStatusPill(state: .ready, label: count == 1 ? "1 eintrag" : "\(count) einträge")
  }

  private var archiveSection: some View {
    SettingsSection(
      "transkriptions-archiv",
      icon: "archivebox",
      trailing: { archivePill }
    ) {
      // Status → Action: Toggle first, privacy detail behind disclosure.
      Toggle(
        "transkriptionen lokal archivieren",
        isOn: $appState.isArchiveEnabled
      )
      .toggleStyle(.switch)
      .controlSize(.small)

      InfoDisclosure("datenschutz") {
        Text(
          "aus für maximale privatsphäre. wenn aktiv, werden roh- und endtext der letzten "
            + "90 tage on-device gespeichert (nur du, kein audio, nichts verlässt den Mac). "
            + "das archiv speichert nur text. gelernte begriffe pflegst du im tab \u{201E}vokabular\u{201C}."
        )
      }

      if appState.isArchiveEnabled {
        archiveList
      } else {
        EmptyStateCard(
          icon: "archivebox",
          title: "archiv ist aus",
          caption:
            "es wird nichts gespeichert. aktiviere das archiv, um transkriptionen on-device "
            + "festzuhalten und memory zu speisen.",
          accent: .primary
        )
      }

      // Always-visible bottom action bar: open window on the left, delete on the right.
      // 'Archiv löschen' is rendered but disabled when archiving is off or archive is empty,
      // preventing layout jumps.
      bottomActionBar
    }
  }

  private var bottomActionBar: some View {
    HStack {
      Button {
        NotificationCenter.default.post(name: .openArchiveWindow, object: nil)
      } label: {
        Label("archiv-fenster öffnen …", systemImage: "macwindow")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))

      Spacer()

      Button {
        showClearArchiveConfirm = true
      } label: {
        Label("archiv löschen", systemImage: "trash")
      }
      .buttonStyle(PopoverActionButtonStyle(.danger))
        .disabled(!appState.isArchiveEnabled || appState.archiveStore.entries.isEmpty)
        .accessibilityLabel("Archiv löschen")
        .confirmationDialog(
          "archiv löschen?",
          isPresented: $showClearArchiveConfirm,
          titleVisibility: .visible
        ) {
          Button("löschen", role: .destructive) { appState.clearArchive() }
          Button("abbrechen", role: .cancel) {}
        } message: {
          Text(
            "alle archivierten transkriptionen werden on-device entfernt. das lässt sich nicht rückgängig machen."
          )
        }
    }
    .padding(.top, 2)
  }

  /// Inline condensed list: only the newest few entries, with a button that opens the full
  /// archive in its own standalone window. The full list lives in `ArchiveWindowView`.
  private static let inlinePreviewLimit = 3

  @ViewBuilder
  private var archiveList: some View {
    let all = appState.archiveStore.entries
    let preview = Array(all.prefix(Self.inlinePreviewLimit))

    if preview.isEmpty {
      Text("noch keine einträge. neue transkriptionen erscheinen hier nach tag.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    } else {
      VStack(spacing: 6) {
        ForEach(preview) { entry in
          ArchiveEntryRow(
            entry: entry,
            appState: appState,
            showActions: false,
            onDelete: { appState.archiveStore.delete(entry.id) }
          )
        }
      }
      .padding(.top, 4)
    }
  }
}

// accentColorValue is defined in MenuBarStyle.swift
