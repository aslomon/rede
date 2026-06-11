import SwiftUI

/// "Kontext / Wo du diktierst" — the on-device Office-Memory overview shown in the archive window.
/// A compact aggregate of the most-used destinations plus a short recent list. Metadata only,
/// never the dictated text. Reuses `SettingsSection`, `MenuBarTokens` and the project type styles.
struct PasteContextSection: View {
  @Bindable var appState: AppState

  private static let recentLimit = 8

  var body: some View {
    // Plain heading + content (NOT a carded SettingsSection): in the archive window the row list is
    // already made of cards, so a box here produced a box-in-box. Matches the popover section style.
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(text: "kontext · wo du diktierst", icon: "scope")
      Text("lokal protokolliert (nur du), nur mit dem archiv. kein text — nur, wo du diktierst.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 12) {
        if appState.pasteContexts.isEmpty {
          emptyState
        } else {
          aggregate
          recentList
        }
      }
    }
  }

  // MARK: - Empty state

  private var emptyState: some View {
    Text(
      "noch nichts protokolliert. sobald du diktierst, erscheint hier, wo der text gelandet ist."
    )
    .font(.system(size: 11))
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Aggregate

  private var aggregate: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("du diktierst meist in:")
        .font(.system(size: 11, weight: .semibold))
      FlowLayout(spacing: 6) {
        ForEach(appState.topPasteContexts.prefix(6), id: \.0) { category, count in
          CategoryChip(category: category, count: count)
        }
      }
    }
  }

  // MARK: - Recent list

  private var recentList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("zuletzt")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      VStack(spacing: 6) {
        ForEach(appState.pasteContexts.prefix(Self.recentLimit)) { context in
          PasteContextRow(context: context)
        }
      }
    }
  }

  // MARK: - Clear

  private var clearButton: some View {
    DestructiveClearButton(
      "verlauf löschen",
      message:
        "das lokale kontext-protokoll (nur metadaten — wo du diktiert hast) wird entfernt. das lässt sich nicht rückgängig machen."
    ) {
      appState.clearPasteContexts()
    }
  }
}

// MARK: - Category chip

/// Capsule chip with the category's SF symbol + German name + count.
/// Accent follows DESIGN.md status colours:
///   browser/web → blue, code/editor/IDE → green, email/chat/communication → orange,
///   everything else → .secondary (no accent association).
private struct CategoryChip: View {
  let category: PasteContextCategory
  let count: Int

  @Environment(\.colorScheme) private var colorScheme

  private var accent: Color {
    switch category {
    case .browser:
      return .blue
    case .code, .terminal:
      return .green
    case .email, .chat:
      return .orange
    case .notes, .document, .other:
      return .secondary
    }
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: category.symbolName)
        .font(.system(size: 9, weight: .semibold))
      Text("\(category.displayName) (\(count))")
        .font(.system(size: 10.5, weight: .medium))
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule().fill(MenuBarTokens.tintFill(accent, colorScheme: colorScheme))
    )
    .overlay(
      Capsule().strokeBorder(
        MenuBarTokens.tintStroke(accent, colorScheme: colorScheme), lineWidth: 0.5)
    )
  }
}

// MARK: - Recent row

/// One destination: app name + window title + a small category badge + relative time.
/// Uses .liquidGlassCard(cornerRadius: 8) in place of manual fill + overlay.
private struct PasteContextRow: View {
  let context: PasteContext

  @Environment(\.colorScheme) private var colorScheme

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.unitsStyle = .short
    return formatter
  }()

  private var appLabel: String {
    let name = (context.appName ?? "").trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "unbekannte app" : name
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: context.category.symbolName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(appLabel)
            .font(.system(size: 11.5, weight: .semibold))
            .lineLimit(1)
          Text(context.category.displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
              Capsule().fill(MenuBarTokens.tintFill(.secondary, colorScheme: colorScheme))
            )
        }
        if let title = context.windowTitle, !title.isEmpty {
          Text(title)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 6)

      Text(Self.relativeFormatter.localizedString(for: context.date, relativeTo: Date()))
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize()
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassCard(cornerRadius: 8)
  }
}
