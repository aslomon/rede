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
  /// The dictated text, shown in the `.copyOnly` fallback card.
  var copyOnlyText: String?
  var pendingVariants: PendingRewriteVariants?
  /// Invoked when the user confirms (stop/checkmark).
  var onStop: () -> Void
  /// Invoked when the user cancels (X).
  var onCancel: () -> Void
  /// Invoked from the `.copyOnly` card's Copy button with the dictated text.
  var onCopy: (String) -> Void = { _ in }
  var onChooseVariant: (RewriteVariant.ID) -> Void = { _ in }
  var onCopyVariant: (RewriteVariant.ID) -> Void = { _ in }
  /// Invoked from the `.copyOnly` card's dismiss (✕).
  var onDismiss: () -> Void = {}

  @State private var isHovering = false

  private let pillHeight: CGFloat = 32

  var body: some View {
    Group {
      if phase == .failed {
        failedContent
      } else if phase == .copyOnly {
        copyOnlyContent
      } else if phase == .variantChoice {
        variantChoiceContent
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
    .modifier(PillGlassSurface())
  }

  /// Fallback card when auto-paste couldn't land: the dictated text in a scrollable, selectable area
  /// with a Copy button (and a ⌘V hint), so the result is never silently stuck on the clipboard.
  ///
  /// Design: three-zone card (header / body / footer) on a rounded-rect glass surface — NOT a
  /// capsule — so the expanded layout reads cleanly. A thin `.separator`-opacity stroke traces the
  /// card edge. The Copy action is a filled accent capsule (prominent CTA); ⌘V hint sits in muted
  /// caption beside it. The dismiss target is a 20×20 circle with a `.tertiary`-foreground ✕.
  private var copyOnlyContent: some View {
    VStack(alignment: .leading, spacing: 0) {

      // ── Header ──────────────────────────────────────────────────────────
      HStack(spacing: 6) {
        Image(systemName: "clipboard")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(accentColor)
        Text("nicht eingefügt — liegt bereit")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        CopyOnlyDismissButton(action: onDismiss)
      }
      .padding(.horizontal, 12)
      .padding(.top, 11)
      .padding(.bottom, 8)

      // ── Divider ─────────────────────────────────────────────────────────
      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(height: 0.5)
        .padding(.horizontal, 0)

      // ── Body ────────────────────────────────────────────────────────────
      ScrollView(.vertical, showsIndicators: false) {
        Text(copyOnlyText ?? "")
          .font(.system(size: 11.5))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .lineSpacing(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
      }
      .frame(maxHeight: 140)

      // ── Divider ─────────────────────────────────────────────────────────
      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(height: 0.5)

      // ── Footer ──────────────────────────────────────────────────────────
      HStack(spacing: 8) {
        Button {
          onCopy(copyOnlyText ?? "")
        } label: {
          Text("kopieren")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text kopieren")
        .help("Text in die Zwischenablage kopieren")

        Text("oder ⌘V")
          .font(.system(size: 10.5))
          .foregroundStyle(Color.secondary.opacity(0.75))

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 10)
    }
    .frame(width: 320)
    .modifier(CardGlassSurface())
  }

  // MARK: - Layout

  // The pill keeps its per-mode accent (mode cueing). rede branding lives in the WRITING — the
  // lowercase voice across status/error/copied/variant copy — not in recoloring the live state.
  private var tint: Color { phase == .cancelled ? .red : accentColor }

  /// Spoken summary of the pill's current state for VoiceOver.
  private var pillAccessibilityLabel: String {
    switch phase {
    case .failed: return "fehler: \(errorMessage ?? "")"
    case .copyOnly: return "nicht eingefügt — liegt in der zwischenablage: \(copyOnlyText ?? "")"
    case .variantChoice: return "zwei versionen bereit. wähl eine zum einfügen."
    case .processing: return "wird transkribiert"
    default: return "läuft — ich hör zu"
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
    .modifier(PillGlassSurface())
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

// MARK: - Glass Modifiers

/// Applies the pill's background surface.
/// macOS 26+: native Liquid Glass capsule (the real design).
/// macOS 14–25: a clean material capsule with one quiet shadow (no gradients, no blends).
private struct PillGlassSurface: ViewModifier {
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

/// Applies a rounded-rect glass surface for expanded cards (copyOnly, etc.).
/// macOS 26+: native Liquid Glass in a rounded rect (radius 14).
/// macOS 14–25: regularMaterial + stroke border + shaped shadow.
struct CardGlassSurface: ViewModifier {
  private let radius: CGFloat = 14

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(.regular, in: .rect(cornerRadius: radius))
    } else {
      content
        .background(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
    }
  }
}

// MARK: - Dismiss Button

/// Small circular dismiss (✕) used in the copyOnly card header.
/// Shows a subtle tinted background on hover so the hit target is visible without being heavy.
struct CopyOnlyDismissButton: View {
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(isHovering ? Color.primary.opacity(0.7) : Color.primary.opacity(0.35))
        .frame(width: 20, height: 20)
        .background(
          Circle()
            .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
        )
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovering = hovering
      }
    }
    .accessibilityLabel("Schließen")
    .help("Schließen")
  }
}
