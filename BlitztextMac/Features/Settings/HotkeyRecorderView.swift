import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
  @Bindable var appState: AppState
  let modeID: ModeConfig.ID

  @Environment(\.colorScheme) private var colorScheme
  @State private var isRecording = false
  @State private var draftCapture = HotkeyCapture.empty

  private var config: HotkeyConfig {
    appState.hotkeyConfig(for: modeID)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Text("tastenkürzel")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer()
        Toggle("aktiv", isOn: isEnabled)
          .toggleStyle(.switch)
          .controlSize(.mini)
      }

      // Fixed-layout button row: cancel (xmark) always leftmost, confirm (checkmark) always
      // rightmost of the trailing pair. Opacity toggles prevent layout jumps (spec change 11).
      HStack(spacing: 8) {
        Button {
          draftCapture = .empty
          appState.setHotkeyRecordingActive(true)
          isRecording = true
        } label: {
          HStack(spacing: 8) {
            Image(systemName: isRecording ? "record.circle" : "keyboard")
              .font(.system(size: 12, weight: .semibold))
            shortcutPreview
            Spacer(minLength: 0)
          }
          .frame(minHeight: 30)
        }
        .buttonStyle(PopoverActionButtonStyle(isRecording ? .warning : .secondary))
        .disabled(!config.isEnabled)
        .help("tastenkombination aufnehmen")

        // Cancel / clear — always leftmost of trailing pair
        Button {
          if isRecording {
            cancelRecording()
          } else {
            clearShortcut()
          }
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(PopoverIconButtonStyle(.quiet))
        .disabled(isRecording ? false : (!config.isConfigured || !config.isEnabled))
        .help(isRecording ? "aufnahme abbrechen" : "tastenkombination löschen")
        .accessibilityLabel(isRecording ? "Aufnahme abbrechen" : "Tastenkombination löschen")

        // Confirm — always rightmost; invisible and disabled when not recording
        Button {
          commitDraftCapture()
        } label: {
          Image(systemName: "checkmark")
        }
        .buttonStyle(PopoverIconButtonStyle(.primary))
        .disabled(!canCommitDraftCapture)
        .help("aufnahme übernehmen")
        .accessibilityLabel("Aufnahme übernehmen")
        .opacity(isRecording ? 1 : 0)
        .allowsHitTesting(isRecording)
      }

      // Ghost capture view hidden from VoiceOver tree (spec change 10)
      HotkeyCaptureView(
        isRecording: $isRecording,
        onChange: { draftCapture = $0 },
        onCapture: applyCapture
      )
      .frame(width: 1, height: 1)
      .opacity(0.01)
      .accessibilityHidden(true)

      // Status banner: shown only for conflict (orange tint) or active recording (spec change 12).
      // Idle/configured state removed — reclaims ~40pt per card.
      if showStatusBanner {
        HStack(spacing: 6) {
          Image(systemName: statusIcon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(statusColor)
          Text(statusText)
            .font(.system(size: 10.5))
            .foregroundStyle(statusColor)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(statusFill)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(statusStroke, lineWidth: 0.5)
        )
      }
    }
    .onChange(of: isRecording) { _, value in
      appState.setHotkeyRecordingActive(value)
      if !value { draftCapture = .empty }
    }
    .onDisappear {
      appState.setHotkeyRecordingActive(false)
      draftCapture = .empty
    }
  }

  @ViewBuilder
  private var shortcutPreview: some View {
    if isRecording {
      if draftCapture.isConfigured {
        HotkeyKeycapRow(parts: draftCapture.labelParts)
      } else {
        Text("jetzt tasten drücken")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
      }
    } else if config.isConfigured {
      HotkeyKeycapRow(parts: config.labelParts)
    } else {
      Text("kombination aufnehmen")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }

  private var isEnabled: Binding<Bool> {
    Binding(
      get: { config.isEnabled },
      set: { value in
        appState.updateHotkey(id: modeID) { hotkey in
          hotkey.isEnabled = value
        }
      }
    )
  }

  /// Banner is visible only for conflict (orange) or active recording — idle state is hidden (spec change 12).
  private var showStatusBanner: Bool {
    statusConflictLabel != nil || isRecording
  }

  private var statusText: String {
    if let conflict = statusConflictLabel { return conflict }
    // Only reached when isRecording is true (showStatusBanner guard)
    return "aufnahme aktiv. tastenkürzel sind solange pausiert."
  }

  private var statusIcon: String {
    statusConflictLabel != nil ? "exclamationmark.triangle.fill" : "record.circle"
  }

  private var statusColor: Color {
    statusConflictLabel != nil ? .orange : .secondary
  }

  private var statusFill: Color {
    if statusConflictLabel != nil {
      return MenuBarTokens.tintFill(.orange, colorScheme: colorScheme)
    }
    // Recording-active state: neutral card fill, no tint
    return MenuBarTokens.cardFill(colorScheme: colorScheme)
  }

  private var statusStroke: Color {
    if statusConflictLabel != nil {
      return MenuBarTokens.tintStroke(.orange, colorScheme: colorScheme)
    }
    return MenuBarTokens.cardStroke(colorScheme: colorScheme)
  }

  private var statusConflictLabel: String? {
    if isRecording {
      return appState.hotkeyConflictLabel(for: draftHotkeyConfig, excluding: modeID)
    }
    return appState.hotkeyConflictLabel(for: modeID)
  }

  private var canCommitDraftCapture: Bool {
    draftCapture.isConfigured
      && appState.hotkeyConflictLabel(for: draftHotkeyConfig, excluding: modeID) == nil
  }

  private var draftHotkeyConfig: HotkeyConfig {
    HotkeyConfig(
      modeID: modeID,
      modifiers: draftCapture.normalizedModifiers,
      keys: draftCapture.normalizedKeys,
      isEnabled: true
    )
  }

  private func clearShortcut() {
    appState.updateHotkey(id: modeID) { hotkey in
      hotkey.modifiers = []
      hotkey.keys = []
    }
  }

  private func commitDraftCapture() {
    guard canCommitDraftCapture else { return }
    applyCapture(draftCapture)
    isRecording = false
    draftCapture = .empty
  }

  private func cancelRecording() {
    isRecording = false
    draftCapture = .empty
    appState.setHotkeyRecordingActive(false)
  }

  private func applyCapture(_ capture: HotkeyCapture) {
    appState.updateHotkey(id: modeID) { hotkey in
      hotkey.modifiers = capture.normalizedModifiers
      hotkey.keys = capture.normalizedKeys
    }
  }
}

private struct HotkeyKeycapRow: View {
  let parts: [String]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
        if index > 0 {
          Text("+")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        Text(part)
          .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
          .lineLimit(1)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .liquidGlassKeycap()
      }
    }
  }
}
