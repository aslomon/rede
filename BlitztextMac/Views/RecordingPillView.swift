import SwiftUI

/// A compact floating capsule shown at the top-center of the screen while a workflow records.
///
/// Idle: a static accent dot + live center-mirrored waveform.
/// Hover: morphs to expose stop (checkmark) and cancel (X) affordances.
///
/// macOS 26+: native Liquid Glass via `.glassEffect(in: .capsule)`.
/// macOS 14–25: clean Capsule + .regularMaterial + one quiet shadow. No gradients, no blends.
///
/// Hosted in a borderless non-activating NSPanel by `RecordingPillController`.
struct RecordingPillView: View {
  /// Live mic level (0...1), pushed from the controller each tick.
  var audioLevel: Float
  /// Per-mode accent color. Defaults to transcription blue.
  var accentColor: Color
  /// Recording (live waveform) / processing (working animation) / cancelled (brief red flash) /
  /// failed (red + the error message).
  var phase: PillPhase
  /// The run's error text, shown in the `.failed` state.
  var errorMessage: String?
  /// Invoked when the user confirms (stop/checkmark).
  var onStop: () -> Void
  /// Invoked when the user cancels (X).
  var onCancel: () -> Void

  @State private var isHovering = false

  private let pillHeight: CGFloat = 32

  var body: some View {
    Group {
      if phase == .failed {
        failedContent
      } else {
        pillContent
      }
    }
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.18)) {
        isHovering = hovering
      }
    }
    .animation(.easeInOut(duration: 0.18), value: isHovering)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(pillAccessibilityLabel)
  }

  /// Red error pill: a warning glyph + the actual message (up to 2 lines), so a failed run — most
  /// importantly an eyes-off background-hotkey run — explains itself instead of flashing silently.
  private var failedContent: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.red)
      Text(errorMessage ?? "Fehler")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 240, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .modifier(PillGlassModifier())
  }

  // MARK: - Layout

  private var tint: Color { phase == .cancelled ? .red : accentColor }

  /// Spoken summary of the pill's current state for VoiceOver.
  private var pillAccessibilityLabel: String {
    switch phase {
    case .failed: return "Fehler: \(errorMessage ?? "")"
    case .processing: return "Wird transkribiert"
    default: return "Aufnahme läuft"
    }
  }

  private var pillContent: some View {
    HStack(spacing: 8) {
      recordingDot

      if phase == .cancelled {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.red)
          .transition(.opacity)
      } else if isHovering {
        affordances
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .scale(scale: 0.88)),
              removal: .opacity.combined(with: .scale(scale: 0.88))
            )
          )
      } else {
        PillWaveformView(
          audioLevel: phase == .processing ? 0 : audioLevel,
          accentColor: accentColor,
          isProcessing: phase == .processing
        )
        .accessibilityHidden(true)
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92)),
            removal: .opacity.combined(with: .scale(scale: 0.92))
          )
        )
      }
    }
    .padding(.horizontal, 12)
    .frame(height: pillHeight)
    .modifier(PillGlassModifier())
    .animation(.easeInOut(duration: 0.2), value: phase)
  }

  // MARK: - Subviews

  /// Accent dot — turns red on cancel; gently pulses while processing to signal "working".
  private var recordingDot: some View {
    Circle()
      .fill(tint)
      .frame(width: 6, height: 6)
      .scaleEffect(phase == .processing ? 1.25 : 1.0)
      .opacity(phase == .processing ? 0.65 : 1.0)
      .animation(
        phase == .processing
          ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
          : .default,
        value: phase
      )
      .accessibilityHidden(true)
  }

  private var affordances: some View {
    HStack(spacing: 6) {
      affordanceButton(
        systemName: "checkmark",
        tint: accentColor,
        help: "Enter = beenden",
        accessibilityLabel: "Aufnahme beenden",
        action: onStop
      )
      affordanceButton(
        systemName: "xmark",
        tint: Color.primary.opacity(0.55),
        help: "Abbrechen",
        accessibilityLabel: "Aufnahme abbrechen",
        action: onCancel
      )
    }
  }

  // MARK: - Helpers

  private func affordanceButton(
    systemName: String,
    tint: Color,
    help: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 22, height: 22)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(accessibilityLabel)
  }
}

// MARK: - Glass Modifier

/// Applies the pill's background surface.
/// macOS 26+: native Liquid Glass capsule (the real design).
/// macOS 14–25: a clean material capsule with one quiet shadow (no gradients, no blends).
private struct PillGlassModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(.regular, in: .capsule)
    } else {
      content
        .background(Capsule(style: .continuous).fill(.regularMaterial))
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
  }
}
