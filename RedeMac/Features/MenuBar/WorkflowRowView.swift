import SwiftUI

struct WorkflowRowView: View {
  let type: WorkflowType
  let enabled: Bool
  var customName: String? = nil
  var subtitle: String? = nil
  var hotkeyLabel: String? = nil
  // Spec change #6/#7: parent passes its @Namespace for cross-row glass morphing
  var namespace: Namespace.ID
  let action: () -> Void

  @State private var isHovered = false
  // Spec change #8: selfNamespace as fallback if caller cannot provide one.
  // In practice callers always pass rowNamespace from MainPageView.
  @Namespace private var selfNamespace
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        iconTile
        labelStack
        Spacer()
        HotkeyBadge(label: hotkeyLabel ?? type.hotkeyLabel, enabled: enabled)
          .opacity(enabled ? 1 : 0.4)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      // Spec change #7: .glassRowBackground replaces the rowBackground computed var
      .glassRowBackground(
        id: AnyHashable(type.rawValue),
        namespace: namespace,
        isHovered: isHovered,
        accentColor: type.accentColorValue
      )
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(accessibilityHint)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.5)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
  }

  // MARK: - Accessibility

  private var accessibilityLabel: String {
    "\(customName ?? type.displayName), \(subtitle ?? type.subtitle)"
  }

  private var accessibilityHint: String {
    enabled ? "Startet die Aufnahme" : "Nicht verfügbar — in Einstellungen einrichten"
  }

  // MARK: - Icon tile with per-mode accent

  private var iconTile: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10)
        .fill(
          isHovered && enabled
            ? MenuBarTokens.tintFill(type.accentColorValue, colorScheme: colorScheme)
              .opacity(1.3)  // slightly brighter on hover
            : MenuBarTokens.tintFill(type.accentColorValue, colorScheme: colorScheme)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
              MenuBarTokens.tintStroke(type.accentColorValue, colorScheme: colorScheme),
              lineWidth: 0.5
            )
        )
        .frame(width: 36, height: 36)

      Image(systemName: type.icon)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(type.accentColorValue)
    }
  }

  // MARK: - Name + subtitle + readiness dot

  private var labelStack: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        Text(customName ?? type.displayName)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(enabled ? .primary : .secondary)
          .lineLimit(1)

        if enabled {
          Circle()
            .fill(type.accentColorValue)
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
        } else {
          Image(systemName: "exclamationmark.circle")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
        }
      }

      Text(subtitle ?? type.subtitle)
        .font(.system(size: 11))
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.6))
        .lineLimit(1)
    }
  }
}

// MARK: - Hotkey Badge

struct HotkeyBadge: View {
  let label: String
  let enabled: Bool
  // Spec change #9: colorScheme kept for the disabled opacity path in keycapText
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 3) {
      ForEach(label.components(separatedBy: " + "), id: \.self) { key in
        // Spec change #9: MenuBarTokens.keycapText replaces keyTextColor computed var
        Text(key)
          .font(.system(size: 10.5, weight: .semibold, design: .rounded))
          .foregroundStyle(
            enabled
              ? MenuBarTokens.keycapText(colorScheme: colorScheme)
              : MenuBarTokens.keycapText(colorScheme: colorScheme).opacity(0.4)
          )
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          // Spec change #9: .liquidGlassKeycap() replaces RoundedRectangle fill + strokeBorder
          // On macOS 26: .glassEffect(.clear, in: .rect(cornerRadius: 6))
          // On macOS 14–25: KeycapFallbackModifier (MenuBarTokens.keycapFill/keycapStroke)
          .liquidGlassKeycap()
          // Shadow only on macOS 14–25 path (glass provides its own depth on macOS 26)
          .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.10) : Color.black.opacity(0.06),
            radius: 1.2,
            y: 0.6
          )
      }
    }
  }
}
