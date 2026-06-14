import SwiftUI

// MARK: - Settings primitives
//
// Shared building blocks for the five settings tabs (modi · modelle · vokabular · archiv ·
// system). They keep grouping, empty-state guidance and status badges consistent across tabs and
// codify the DESIGN.md conventions (SectionLabel, card radii, du-form lowercase copy).

/// The ONE settings section container used across all five tabs: a quiet 12pt card
/// (`settingsGroupBackground`) with the heading row INSIDE — `SectionLabel`, an optional trailing
/// status pill, and an optional quiet header action. Replaces the earlier GroupBox styling so
/// every tab reads with the same surface language as the System tab.
struct SettingsSection<Content: View, Trailing: View>: View {
  let label: String
  let icon: String?
  let action: (label: String, perform: () -> Void)?
  let caption: String?
  let trailing: Trailing
  let content: Content

  init(
    _ label: String,
    icon: String? = nil,
    action: (label: String, perform: () -> Void)? = nil,
    caption: String? = nil,
    @ViewBuilder trailing: () -> Trailing,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.icon = icon
    self.action = action
    self.caption = caption
    self.trailing = trailing()
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        SectionLabel(text: label, icon: icon)
        // Status pill sits in the section header (DESIGN.md), right next to the label.
        trailing
        Spacer()
        if let action {
          Button(action.label) { action.perform() }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
        }
      }

      if let caption {
        Text(caption)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      content
    }
    .settingsGroupBackground()
  }
}

extension SettingsSection where Trailing == EmptyView {
  init(
    _ label: String,
    icon: String? = nil,
    action: (label: String, perform: () -> Void)? = nil,
    caption: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      label, icon: icon, action: action, caption: caption, trailing: { EmptyView() },
      content: content)
  }
}

// MARK: - Empty-state card

/// Guidance card shown when a feature has nothing configured yet: an accent-tinted banner with an
/// icon + title row, a caption and an optional inline CTA. Tinted via the flat `.tintBanner` so it
/// reads as actionable guidance, not as another nested section box (the earlier GroupBox version
/// produced box-in-box inside `SettingsSection`).
struct EmptyStateCard: View {
  let icon: String
  let title: String
  let caption: String
  let accent: Color
  let buttonLabel: String?
  let action: (() -> Void)?

  init(
    icon: String,
    title: String,
    caption: String,
    accent: Color,
    buttonLabel: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.icon = icon
    self.title = title
    self.caption = caption
    self.accent = accent
    self.buttonLabel = buttonLabel
    self.action = action
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
        Text(title)
          .font(.system(size: 11.5, weight: .semibold))
      }
      .foregroundStyle(accent)

      Text(caption)
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let buttonLabel, let action {
        Button {
          action()
        } label: {
          Label(buttonLabel, systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    // Flat tint surface (DESIGN.md Flächen-Hierarchie): this card nests inside SettingsSection,
    // so it must not introduce a glass layer.
    .tintBanner(accent)
  }
}

// MARK: - Model select row

/// Compact selectable model row for inline selection in the Modelle tab (Whisper + GGUF): the
/// active model gets one marker only, the leading green check. Inactive rows expose "nutzen".
/// Mirrors the row pattern of the Lokale-Modelle window so selection looks identical everywhere.
struct ModelSelectRow: View {
  let title: String
  let subtitle: String?
  let isActive: Bool
  let select: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isActive ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 11.5, weight: .semibold))
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      if !isActive {
        Button("nutzen", action: select)
          .buttonStyle(PopoverActionButtonStyle(.secondary))
          .accessibilityLabel("\(title) nutzen")
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .tokenCard(cornerRadius: 8)
  }
}

// MARK: - Quiet toggle label

/// Label style for icon-carrying toggles (rede icon language on Schalter): the concept icon
/// renders quiet (10.5pt semibold, secondary, fixed 14pt slot so stacked toggles align); the
/// title keeps whatever font cascades from the call site. Master toggles directly under a
/// same-concept section header stay icon-free — see DESIGN.md.
struct QuietToggleLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.icon
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 14)
      configuration.title
    }
  }
}

// MARK: - Mode hotkey row

/// Read-only per-mode hotkey line shared by the System tab and the onboarding hotkeys step so the
/// two tables never drift: mode icon in its accent colour, display name, keycaps right-aligned.
/// Deliberately NOT a tokenCard — this is information, not an actionable row.
struct ModeHotkeyRow: View {
  let icon: String
  let accent: Color
  let name: String
  /// The configured combination (e.g. "fn + Shift"); nil renders a quiet "nicht gesetzt".
  let hotkeyLabel: String?

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 16)
        .accessibilityHidden(true)
      Text(name)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
      Spacer(minLength: 8)
      if let hotkeyLabel {
        HotkeyBadge(label: hotkeyLabel, enabled: true)
      } else {
        Text("nicht gesetzt")
          .font(.system(size: 10.5))
          .foregroundStyle(.tertiary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Destructive clear button

/// A single red action that confirms via the native `.confirmationDialog`
/// (UX-6) instead of an inline "abbrechen / wirklich löschen" toggle. Unifies the archive-
/// window "verlauf/archiv löschen" buttons (archiv · kontext · verbesserungen) so destructive
/// deletes look and behave identically and each carries a VoiceOver label. The dialog title is
/// derived from `label`; `message` spells out the irreversible, on-device consequence.
struct DestructiveClearButton: View {
  let label: String
  let message: String
  let action: () -> Void

  @State private var showConfirm = false

  init(_ label: String, message: String, action: @escaping () -> Void) {
    self.label = label
    self.message = message
    self.action = action
  }

  var body: some View {
    Button {
      showConfirm = true
    } label: {
      Label(label, systemImage: "trash")
    }
    .buttonStyle(PopoverActionButtonStyle(.danger))
    .accessibilityLabel(label)
    .confirmationDialog("\(label)?", isPresented: $showConfirm, titleVisibility: .visible) {
      Button("löschen", role: .destructive, action: action)
      Button("abbrechen", role: .cancel) {}
    } message: {
      Text(message)
    }
  }
}

// MARK: - Section background

extension View {
  /// Wraps a settings section in a subtle background "div" (DESIGN.md card fill) so each group reads
  /// as a clearly separated block — light enough to group without a heavy box. The single section
  /// surface across ALL settings tabs (used directly by the System tab and via `SettingsSection`).
  func settingsGroupBackground() -> some View {
    self
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.primary.opacity(0.03))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
      )
  }
}
