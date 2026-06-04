import SwiftUI

/// A compact floating capsule shown at the top-center of the screen while a workflow records.
/// Idle state: an accent dot + live waveform + "Aufnahme" label. On hover it morphs to expose
/// two affordances — a stop/checkmark ("Enter = beenden") and an X ("Abbrechen").
///
/// Minimalist, DESIGN.md-aligned: ultraThinMaterial, 0.5pt border, per-mode accent, short
/// easeInOut transitions. Hosted in a borderless, non-activating NSPanel by `RecordingPillController`.
struct RecordingPillView: View {
  /// Live mic level (0...1), pushed from the controller each tick.
  var audioLevel: Float
  /// The recording mode, for the accent color. Defaults to transcription blue.
  var accentColor: Color
  /// Invoked when the user clicks the stop/checkmark affordance (finish recording).
  var onStop: () -> Void
  /// Invoked when the user clicks the X affordance (cancel recording).
  var onCancel: () -> Void

  @State private var isHovering = false

  private var pillHeight: CGFloat { 30 }

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(accentColor)
        .frame(width: 6, height: 6)
        .shadow(color: accentColor.opacity(0.6), radius: 2)

      // Compact live waveform driven by the workflow's audio level.
      WaveformView(audioLevel: audioLevel, isRecording: true, accentColor: accentColor)
        .frame(width: 56, height: 18)
        .clipped()

      if isHovering {
        affordances
          .transition(.opacity.combined(with: .move(edge: .trailing)))
      } else {
        Text("Aufnahme")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: pillHeight)
    .background(
      Capsule(style: .continuous)
        .fill(.ultraThinMaterial)
    )
    .overlay(
      Capsule(style: .continuous)
        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
    )
    .clipShape(Capsule(style: .continuous))
    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.18)) {
        isHovering = hovering
      }
    }
    .animation(.easeInOut(duration: 0.18), value: isHovering)
  }

  private var affordances: some View {
    HStack(spacing: 6) {
      affordanceButton(
        systemName: "checkmark",
        tint: accentColor,
        help: "Enter = beenden",
        action: onStop
      )
      affordanceButton(
        systemName: "xmark",
        tint: .secondary,
        help: "Abbrechen",
        action: onCancel
      )
    }
  }

  private func affordanceButton(
    systemName: String,
    tint: Color,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 20, height: 20)
        .background(
          Circle().fill(Color.primary.opacity(0.06))
        )
        .overlay(
          Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}
