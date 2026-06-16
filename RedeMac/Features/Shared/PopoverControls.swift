import SwiftUI

enum PopoverActionRole {
  case primary
  case secondary
  case warning
  case danger
  case quiet
}

struct PopoverActionButtonStyle: ButtonStyle {
  let role: PopoverActionRole

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme

  init(_ role: PopoverActionRole = .secondary) {
    self.role = role
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(foregroundColor)
      .padding(.horizontal, role == .quiet ? 8 : 10)
      .padding(.vertical, role == .quiet ? 4 : 6)
      .frame(minHeight: role == .quiet ? 24 : 28)
      .background(backgroundShape(configuration: configuration))
      .overlay(borderShape)
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }

  private var foregroundColor: Color {
    guard isEnabled else { return .secondary }
    switch role {
    case .primary: return .white
    case .secondary, .quiet: return .primary
    case .warning: return .orange
    case .danger: return .red
    }
  }

  private func backgroundShape(configuration: Configuration) -> some View {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
      .fill(backgroundColor.opacity(configuration.isPressed ? 0.78 : 1))
  }

  private var borderShape: some View {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
      .strokeBorder(borderColor, lineWidth: role == .quiet ? 0.5 : 0.8)
  }

  private var backgroundColor: Color {
    switch role {
    case .primary:
      return Color.accentColor
    case .secondary:
      return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    case .warning:
      return colorScheme == .dark ? Color.orange.opacity(0.14) : Color.orange.opacity(0.08)
    case .danger:
      return colorScheme == .dark ? Color.red.opacity(0.14) : Color.red.opacity(0.08)
    case .quiet:
      return colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.025)
    }
  }

  private var borderColor: Color {
    switch role {
    case .primary:
      return Color.white.opacity(colorScheme == .dark ? 0.22 : 0.18)
    case .secondary:
      return colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    case .warning:
      return Color.orange.opacity(colorScheme == .dark ? 0.36 : 0.22)
    case .danger:
      return Color.red.opacity(colorScheme == .dark ? 0.36 : 0.22)
    case .quiet:
      return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
  }
}

struct PopoverIconButtonStyle: ButtonStyle {
  let role: PopoverActionRole

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme

  init(_ role: PopoverActionRole = .quiet) {
    self.role = role
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(foregroundColor)
      .frame(width: 28, height: 28)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(backgroundColor.opacity(configuration.isPressed ? 0.65 : 1))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(borderColor, lineWidth: 0.6)
      )
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }

  private var foregroundColor: Color {
    switch role {
    case .danger: return .red
    case .warning: return .orange
    case .primary: return .white
    case .secondary, .quiet: return .secondary
    }
  }

  private var backgroundColor: Color {
    switch role {
    case .primary: return Color.accentColor
    case .danger: return Color.red.opacity(colorScheme == .dark ? 0.13 : 0.07)
    case .warning: return Color.orange.opacity(colorScheme == .dark ? 0.13 : 0.07)
    case .secondary: return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    case .quiet: return colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.025)
    }
  }

  private var borderColor: Color {
    switch role {
    case .primary: return Color.white.opacity(0.18)
    case .danger: return Color.red.opacity(0.24)
    case .warning: return Color.orange.opacity(0.24)
    case .secondary, .quiet:
      return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }
  }
}

struct RedeStatusPill: View {
  enum State {
    case ready
    case warning
    case download
    case local
    case online
    case muted

    var icon: String {
      switch self {
      case .ready: return "checkmark.circle.fill"
      case .warning: return "exclamationmark.triangle.fill"
      case .download: return "arrow.down.circle.fill"
      case .local: return "lock.shield.fill"
      case .online: return "cloud.fill"
      case .muted: return "minus.circle"
      }
    }

    var tint: Color {
      switch self {
      case .ready, .local: return .green
      case .warning: return .orange
      case .download, .online: return .blue
      case .muted: return .secondary
      }
    }
  }

  let state: State
  let label: String

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: state.icon)
        .font(.system(size: 9.5, weight: .semibold))
      Text(label)
        .font(.system(size: 10, weight: .medium))
        .lineLimit(1)
    }
    .foregroundStyle(state.tint)
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(state.tint.opacity(0.10), in: Capsule(style: .continuous))
    .overlay(
      Capsule(style: .continuous)
        .strokeBorder(state.tint.opacity(0.18), lineWidth: 0.5)
    )
  }
}

struct InfoDisclosure<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  @State private var isOpen = false

  init(_ label: String = "details", @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation(.easeInOut(duration: 0.14)) { isOpen.toggle() }
      } label: {
        Label(label, systemImage: isOpen ? "info.circle.fill" : "info.circle")
      }
      .buttonStyle(PopoverActionButtonStyle(.quiet))

      if isOpen {
        content
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }
}
