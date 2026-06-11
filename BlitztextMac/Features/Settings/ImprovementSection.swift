import SwiftUI

/// "Verbesserungen · was du nach dem Diktat änderst" — the on-device improvement-detection overview
/// (MEM-2) shown in the archive window. A short recent list of corrections (app + compact
/// before/after + relative time). PRIVACY-SENSITIVE → only meaningful when the opt-in toggle is on;
/// renders nothing while off so it never implies data is being collected. DESIGN.md tokens.
struct ImprovementSection: View {
  @Bindable var appState: AppState

  private static let recentLimit = 8

  var body: some View {
    if appState.isImprovementDetectionEnabled {
      // Plain heading + content (NOT a carded SettingsSection): the row list is already cards, so a
      // box here was a box-in-box. Matches the popover section style.
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel(
          text: "verbesserungen · was du nach dem diktat änderst", icon: "wand.and.stars")
        Text(
          "lokal protokolliert (nur du). lernt aus deinen korrekturen — wiederkehrende schlägt es "
            + "als festes wörterbuch-wort vor."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 12) {
          if !appState.improvementSuggestions.isEmpty {
            suggestionsBlock
          }
          if appState.improvementObservations.isEmpty {
            emptyState
          } else {
            recentList
          }
        }
      }
    }
  }

  // MARK: - Suggestions (MEM-2b)

  /// Learnable replacements mined from recurring corrections. One-tap "Übernehmen" adds the pair to
  /// the dictation dictionary; "Verwerfen" hides it for this session.
  private var suggestionsBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("lern-vorschläge")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      Text("wiederkehrende korrekturen — als festes wörterbuch-wort übernehmen?")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 6) {
        ForEach(appState.improvementSuggestions) { suggestion in
          ImprovementSuggestionRow(
            suggestion: suggestion,
            onAccept: { appState.acceptImprovementSuggestion(suggestion) },
            onDismiss: { appState.dismissImprovementSuggestion(suggestion) }
          )
        }
      }
    }
  }

  // MARK: - Empty state

  private var emptyState: some View {
    Text(
      "noch keine korrekturen erkannt. sobald du eingefügten text im feld änderst, erscheint die "
        + "verbesserung hier."
    )
    .font(.system(size: 11))
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Recent list

  private var recentList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("zuletzt")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      VStack(spacing: 6) {
        ForEach(appState.improvementObservations.prefix(Self.recentLimit)) { observation in
          ImprovementRow(observation: observation)
        }
      }
    }
  }

  // MARK: - Clear

  private var clearButton: some View {
    DestructiveClearButton(
      "verlauf löschen",
      message:
        "alle erkannten verbesserungen (eingefügter text und deine korrektur) werden on-device entfernt. das lässt sich nicht rückgängig machen."
    ) {
      appState.clearImprovements()
    }
  }
}

// MARK: - Row

/// One correction: app name + a compact before/after (truncated) + relative time. Unchanged
/// observations are dimmed; edited ones show the diff with an arrow.
private struct ImprovementRow: View {
  let observation: ImprovementObservation


  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.unitsStyle = .short
    return formatter
  }()

  private var appLabel: String {
    let name = (observation.appName ?? "").trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "unbekannte app" : name
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      header
      if observation.changed {
        beforeAfter
      } else {
        Text("unverändert übernommen.")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .tokenCard(cornerRadius: 8)
  }

  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: observation.changed ? "pencil.line" : "checkmark")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(observation.changed ? .orange : .secondary)
      Text(appLabel)
        .font(.system(size: 11.5, weight: .semibold))
        .lineLimit(1)
      Spacer(minLength: 6)
      Text(Self.relativeFormatter.localizedString(for: observation.date, relativeTo: Date()))
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize()
    }
  }

  private var beforeAfter: some View {
    // "Eingefügt" = the text rede pasted; "Korrektur" = what the user changed it to. Clearer
    // than the ambiguous "Vorher/Nachher" (it was unclear which side was rede's output).
    VStack(alignment: .leading, spacing: 2) {
      diffLine(label: "eingefügt", text: observation.inserted, accent: .secondary)
      diffLine(label: "korrektur", text: observation.finalText, accent: .primary)
    }
  }

  private func diffLine(label: String, text: String, accent: HierarchicalShapeStyle) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(label)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
        .frame(width: 52, alignment: .leading)
      Text(truncated(text))
        .font(.system(size: 10.5))
        .foregroundStyle(accent)
        .lineLimit(2)
        .truncationMode(.tail)
    }
  }

  private func truncated(_ text: String, limit: Int = 160) -> String {
    let collapsed = text.replacingOccurrences(of: "\n", with: " ")
    guard collapsed.count > limit else { return collapsed }
    return String(collapsed.prefix(limit)) + "…"
  }
}

// MARK: - Suggestion row (MEM-2b)

/// One mined replacement: "from → to (N×)" with Übernehmen / Verwerfen. Tinted distinct from the
/// recorded-correction rows so the actionable suggestion reads as a call to action, not history.
private struct ImprovementSuggestionRow: View {
  let suggestion: ImprovementMiner.Suggestion
  let onAccept: () -> Void
  let onDismiss: () -> Void


  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "wand.and.stars")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.blue)

      HStack(spacing: 4) {
        Text(suggestion.from)
          .font(.system(size: 11.5, weight: .semibold))
          .lineLimit(1)
        Image(systemName: "arrow.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
        Text(suggestion.to)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.blue)
          .lineLimit(1)
        Text("\(suggestion.count)×")
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 6)

      Button(action: onAccept) {
        Label("übernehmen", systemImage: "checkmark")
      }
      .buttonStyle(PopoverActionButtonStyle(.primary))
      .accessibilityLabel("Vorschlag übernehmen: \(suggestion.from) zu \(suggestion.to)")
      Button(action: onDismiss) {
        Label("verwerfen", systemImage: "xmark")
      }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
      .accessibilityLabel("Vorschlag verwerfen: \(suggestion.from) zu \(suggestion.to)")
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .tintBanner(.blue, cornerRadius: 8)
  }
}
