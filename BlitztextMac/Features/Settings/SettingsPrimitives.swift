import SwiftUI

// MARK: - Settings primitives
//
// Shared building blocks for the four settings tabs (Prompts · Modelle · Archiv · System).
// They keep grouping, empty-state guidance and status badges consistent across tabs and
// codify the DESIGN.md conventions (SectionLabel, SubtleButtonStyle, card radii, du-form text).

/// A native macOS settings group. Prefer SwiftUI's stock `GroupBox` so macOS 26 can provide the
/// platform surface; custom Liquid Glass should stay at the popover/window level.
struct SettingsSection<Content: View>: View {
  let label: String
  let action: (label: String, perform: () -> Void)?
  let caption: String?
  @ViewBuilder let content: Content

  init(
    _ label: String,
    action: (label: String, perform: () -> Void)? = nil,
    caption: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.action = action
    self.caption = caption
    self.content = content()
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        // Heading lives INSIDE the box (not as the GroupBox label floating above it) so the section
        // title visually belongs to its own container.
        HStack(spacing: 8) {
          SectionLabel(text: label)
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
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Empty-state card

/// Guidance card shown when a feature has nothing configured yet. Mirrors the visual language of
/// `LocalLLMModelPicker.emptyStateGuidance`: an accent-tinted fill, soft accent border and an
/// optional inline CTA. Use it to nudge the user toward the step that unblocks the feature.
struct EmptyStateCard: View {
  let icon: String
  let title: String
  let caption: String
  let accent: Color
  let buttonLabel: String?
  let action: (() -> Void)?

  @Environment(\.colorScheme) private var colorScheme

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
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        Text(caption)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if let buttonLabel, let action {
          Button {
            action()
          } label: {
            Label(buttonLabel, systemImage: "arrow.right.circle.fill")
              .font(.system(size: 11, weight: .semibold))
          }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label(title, systemImage: icon)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(accent)
    }
  }
}

// MARK: - Status badge

/// Compact availability badge reusing the project's status icons (DESIGN.md):
/// green check = ready, blue down-arrow = pending download, orange triangle = needs attention.
struct SettingsStatusBadge: View {
  enum State {
    case ready
    case download
    case warning

    var iconName: String {
      switch self {
      case .ready: return "checkmark.circle.fill"
      case .download: return "arrow.down.circle.fill"
      case .warning: return "exclamationmark.triangle.fill"
      }
    }

    var tint: Color {
      switch self {
      case .ready: return .green
      case .download: return .blue
      case .warning: return .orange
      }
    }
  }

  let state: State
  let label: String

  init(_ state: State, label: String) {
    self.state = state
    self.label = label
  }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: state.iconName)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(state.tint)
      Text(label)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Destructive clear button

/// A single red `SubtleButtonStyle` action that confirms via the native `.confirmationDialog`
/// (UX-6) instead of an inline "Abbrechen / Wirklich löschen" toggle. Unifies the three archive-
/// window "Verlauf/Archiv löschen" buttons (Archiv · Kontext · Verbesserungen) so destructive
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
    Button(label) { showConfirm = true }
      .font(.system(size: 10, weight: .medium))
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
  /// as a clearly separated block — light enough to group without a heavy box. Matches the Modelle bands.
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
