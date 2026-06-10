import SwiftUI

/// "Deine Diktate" (R2-FT-stats): a compact, engaging summary of the EXISTING archive — runs,
/// dictated words, an estimate of the typing time saved and the total recording time, plus a
/// per-mode mini-breakdown. Read-only over `AppState.dictationStats`; no new capture, no privacy
/// cost. Reuses `SettingsSection`, `MenuBarTokens` and the DESIGN.md type styles.
struct DictationStatsSection: View {
  @Bindable var appState: AppState

  @Environment(\.colorScheme) private var colorScheme

  private var stats: DictationStats { appState.dictationStats }

  var body: some View {
    // Plain heading + content (NOT a carded SettingsSection): the stat tiles are already a card, so
    // a box here was a box-in-box. Matches the popover section style.
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(text: "deine diktate")
      Text("aus dem lokalen archiv berechnet. keine neue aufzeichnung, kein datenfluss.")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if stats.isEmpty {
        emptyState
      } else {
        VStack(alignment: .leading, spacing: 12) {
          statTiles
          if !stats.perMode.isEmpty {
            modeBreakdown
          }
        }
      }
    }
  }

  // MARK: - Empty state

  private var emptyState: some View {
    Text("noch keine diktate aufgezeichnet — aktiviere das archiv.")
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Stat tiles

  /// 2×2 grid rather than a single 4-wide `HStack`: at the archive window's narrow min width the
  /// four icon+caption+value tiles would clip. The grid wraps to two rows and stays scannable.
  /// Uses .liquidGlassCard(cornerRadius: 10) in place of manual fill + overlay.
  private var statTiles: some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
      GridRow {
        statTile("waveform", "läufe gesamt", "\(stats.totalRuns)")
        statTile(
          "text.word.spacing", "wörter diktiert", DictationStatsFormat.count(stats.totalWords))
      }
      GridRow {
        statTile(
          "hourglass", "zeit gespart",
          "≈ \(DictationStatsFormat.duration(stats.estimatedTypingSecondsSaved))")
        statTile(
          "mic", "aufnahmezeit",
          DictationStatsFormat.duration(stats.totalRecordingSeconds))
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .liquidGlassCard(cornerRadius: 10)
  }

  /// Icon + value + caption tile, mirroring `LocalModelsView.systemStat`.
  private func statTile(_ symbol: String, _ caption: String, _ value: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(caption).font(.system(size: 9.5)).foregroundStyle(.secondary)
        Text(value).font(.system(size: 12, weight: .semibold))
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Per-mode breakdown

  /// Compact FlowLayout of mode chips. Each chip's tint derives from its mode's accent color
  /// (DESIGN.md: blue/green/purple/orange/cyan per mode), replacing the flat dot-separated Text.
  private var modeBreakdown: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("nach modus")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      FlowLayout(spacing: 6) {
        ForEach(stats.perMode, id: \.mode) { entry in
          ModeChip(
            label: "\(appState.displayName(for: entry.mode)) \(entry.runs)",
            accent: entry.mode.accentColorValue
          )
        }
      }
    }
  }
}

// MARK: - Mode chip

/// Small capsule chip with a mode-accent tint. Used in modeBreakdown.
private struct ModeChip: View {
  let label: String
  let accent: Color

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Text(label)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(.primary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule().fill(MenuBarTokens.tintFill(accent, colorScheme: colorScheme))
      )
      .overlay(
        Capsule().strokeBorder(
          MenuBarTokens.tintStroke(accent, colorScheme: colorScheme), lineWidth: 0.5)
      )
  }
}

// MARK: - German formatting

/// Pure, locale-pinned (German) formatting helpers for the stats view. Durations read as
/// "≈ 12 Min" / "≈ 1,5 Std" with a comma decimal; counts get a thousands grouping.
enum DictationStatsFormat {
  /// Compact German duration: seconds → "X Sek" (< 60s), "X Min" (< 60min), else "X,Y Std".
  static func duration(_ seconds: Double) -> String {
    let safe = max(seconds, 0)
    if safe < 60 {
      return "\(Int(safe.rounded())) Sek"
    }
    let minutes = safe / 60
    if minutes < 60 {
      return "\(Int(minutes.rounded())) Min"
    }
    let hours = minutes / 60
    return "\(decimal(hours)) Std"
  }

  /// Thousands-grouped count in German locale (e.g. 1234 → "1.234").
  static func count(_ value: Int) -> String {
    countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  /// One-decimal German number with a comma separator, trailing ",0" trimmed (1.5 → "1,5", 2 → "2").
  private static func decimal(_ value: Double) -> String {
    decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  private static let countFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  private static let decimalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return formatter
  }()
}
