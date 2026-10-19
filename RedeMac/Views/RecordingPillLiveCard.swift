import SwiftUI

/// The recording pill while live transcription is on: the usual dot + waveform header with a
/// fixed-size text window underneath. The window never resizes with the text (so the floating
/// panel never jumps); it shows the tail of the transcript at a word boundary, with text that may
/// still change drawn quieter than text that is settled. Display only — nothing here is typed.
struct RecordingPillLiveCard: View {
  let live: LiveTranscriptModel
  let audioLevel: Float
  let accentColor: Color
  let isHovering: Bool
  let onStop: () -> Void
  let onCancel: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      textWindow
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .frame(width: LiquidGlass.pillExpandedWidth, alignment: .leading)
    .fontDesign(.rounded)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("live-text")
    .accessibilityValue(live.accessibilityValue)
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(RedeBrand.violet)
        .frame(width: 6, height: 6)
      PillWaveformView(audioLevel: audioLevel, accentColor: accentColor, isProcessing: false)
      Text("live")
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      if isHovering {
        HStack(spacing: 6) {
          headerButton("checkmark", tint: accentColor, label: "Aufnahme beenden", action: onStop)
          headerButton(
            "xmark", tint: Color.primary.opacity(0.55), label: "Aufnahme abbrechen",
            action: onCancel)
        }
        .transition(.opacity)
      }
    }
    .frame(height: 22)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isHovering)
  }

  private func headerButton(
    _ systemName: String, tint: Color, label: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 22, height: 22)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }

  // MARK: - Text window

  /// Two lines at 11.5pt; the height is fixed so the panel stays still while words arrive.
  private var textWindow: some View {
    Group {
      if let note = live.note {
        noteRow(note)
      } else {
        transcriptText
      }
    }
    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .topLeading)
    .accessibilityHidden(true)
  }

  private var transcriptText: some View {
    let tail = live.tail
    return Text(styledTail(tail))
      .font(.system(size: 11.5))
      .lineSpacing(2)
      .lineLimit(2)
      .truncationMode(.head)
      .multilineTextAlignment(.leading)
  }

  private func styledTail(_ tail: LiveTranscriptModel.Tail) -> AttributedString {
    var result = AttributedString(tail.isTruncated ? "… " : "")
    result.foregroundColor = .secondary
    var settled = AttributedString(tail.stable)
    settled.foregroundColor = .primary
    var pending = AttributedString(
      (tail.stable.isEmpty || tail.provisional.isEmpty ? "" : " ") + tail.provisional)
    pending.foregroundColor = .secondary
    result.append(settled)
    result.append(pending)
    return result
  }

  private func noteRow(_ note: LiveTranscriptModel.Note) -> some View {
    HStack(spacing: 6) {
      Image(systemName: note.symbolName)
        .font(.system(size: 10, weight: .semibold))
      Text(note.copy)
        .font(.system(size: 11))
    }
    .foregroundStyle(.secondary)
  }
}

extension LiveTranscriptModel.Note {
  /// Calm, factual copy. A stopped live session is not an error: the recording is still kept.
  var copy: String {
    switch self {
    case .connecting: return "verbinde live-text …"
    case .listening: return "ich höre zu …"
    case .finishing: return "letzte worte …"
    case .fallsBackToRecording: return "live-text pausiert — ich transkribiere danach."
    }
  }

  var symbolName: String {
    switch self {
    case .connecting, .finishing: return "waveform"
    case .listening: return "mic"
    case .fallsBackToRecording: return "arrow.triangle.branch"
    }
  }
}
