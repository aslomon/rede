import AppKit
import SwiftUI

// MARK: - Archive entry row (raw -> final on disclosure, + FT-3 reuse actions)

/// One archived run. Tap to expand (Roh / Endtext). When `showActions` is on (the standalone
/// archive window) it also offers FT-3 "Archiv wiederverwenden": copy the text or RE-RUN the
/// rewrite on the stored raw transcript in a chosen mode — no new recording.
/// `showActions: false` (the condensed inline preview) renders the plain, action-free row.
struct ArchiveEntryRow: View {
  let entry: ArchiveEntry
  let appState: AppState
  var showActions: Bool = false
  let onDelete: () -> Void

  @State private var expanded = false

  private var displayName: String {
    let storedName = entry.modeName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return storedName?.isEmpty == false ? storedName ?? "" : appState.displayName(for: entry.mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      disclosureHeader

      if !expanded {
        Text(entry.finalText)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      } else {
        expandedContent
      }
    }
    .padding(10)
    // Flat token row — the app-wide list-row surface (DESIGN.md Flächen-Hierarchie).
    .tokenCard(cornerRadius: 8)
  }

  // MARK: - Header

  private var disclosureHeader: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
    } label: {
      HStack(spacing: 8) {
        Circle()
          .fill(entry.mode.accentColorValue)
          .frame(width: 6, height: 6)

        VStack(alignment: .leading, spacing: 1) {
          Text(displayName)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary)
          Text(timeLabel)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: expanded ? "chevron.up" : "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(displayName), \(timeLabel)")
    .accessibilityHint(expanded ? "Eintrag einklappen" : "Eintrag ausklappen")
  }

  // MARK: - Expanded content

  private var expandedContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      labelledText(label: "Roh", text: entry.rawTranscript)
      if entry.finalText != entry.rawTranscript {
        labelledText(label: "Endtext", text: entry.finalText)
      }

      if showActions {
        ArchiveEntryRowActions(entry: entry, appState: appState)
      }

      HStack {
        Spacer()
        Button(action: onDelete) {
          Image(systemName: "trash")
        }
        .buttonStyle(PopoverIconButtonStyle(.danger))
        .accessibilityLabel("Eintrag löschen")
      }
    }
    .padding(.top, 2)
  }

  private func labelledText(label: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
      Text(text.isEmpty ? "—" : text)
        .font(.system(size: 11))
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var timeLabel: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.dateFormat = "HH:mm"
    let time = formatter.string(from: entry.date)
    let duration = String(format: "%.0f s", entry.durationSec)
    return "\(time) · \(duration)"
  }
}
