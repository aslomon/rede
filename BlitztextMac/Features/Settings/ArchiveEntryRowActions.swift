import AppKit
import SwiftUI

// MARK: - FT-3 reuse actions (copy + re-run a rewrite on the stored transcript)

/// The "Archiv wiederverwenden" action strip under an expanded entry: copy the final or raw text,
/// or RE-RUN the rewrite on the stored raw transcript in a CHOSEN rewrite mode (no new recording).
/// Only mounted in the standalone archive window (`ArchiveEntryRow(showActions: true)`).
struct ArchiveEntryRowActions: View {
  let entry: ArchiveEntry
  let appState: AppState

  @Environment(\.colorScheme) private var colorScheme
  @State private var copiedLabel: String?
  @State private var isRerunning = false
  @State private var rerunResult: String?
  @State private var rerunError: String?
  @State private var rerunModeName: String?
  /// Quiet note when the re-run fell back to a different model than requested (B6). `nil` = hidden.
  @State private var rerunFallbackNote: String?

  /// Brief "Kopiert ✓" feedback auto-resets after this many seconds.
  private static let feedbackResetSeconds: UInt64 = 2

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      actionBar
      if let copiedLabel {
        feedbackLine(text: "\(copiedLabel) kopiert ✓", color: .green)
      }
      rerunBlock
    }
  }

  // MARK: - Action bar

  private var actionBar: some View {
    HStack(spacing: 6) {
      copyButton(title: "kopieren", text: entry.finalText, feedback: "endtext")
      copyButton(title: "transkript kopieren", text: entry.rawTranscript, feedback: "transkript")
      Spacer()
      rerunMenu
    }
  }

  private func copyButton(title: String, text: String, feedback: String) -> some View {
    Button(title) { copy(text, feedback: feedback) }
      .buttonStyle(PopoverActionButtonStyle(.secondary))
      .disabled(text.isEmpty)
      .accessibilityLabel("\(title) in die Zwischenablage")
  }

  private var rerunMenu: some View {
    Menu {
      ForEach(rewriteModes) { mode in
        Button(appState.displayName(for: mode)) { rerun(as: mode) }
      }
    } label: {
      HStack(spacing: 4) {
        if isRerunning {
          ProgressView().controlSize(.small).scaleEffect(0.6)
        } else {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 9, weight: .semibold))
        }
        Text("neu umschreiben …")
          .font(.system(size: 11, weight: .semibold))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(minHeight: 28)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(rerunMenuBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(rerunMenuBorder, lineWidth: 0.8)
      )
    }
    .fixedSize()
    .disabled(isRerunning || entry.rawTranscript.isEmpty)
    .accessibilityLabel("Rohtranskript in einem Modus neu umschreiben")
  }

  private var rerunMenuBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
  }

  private var rerunMenuBorder: Color {
    colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
  }

  private var rewriteModes: [ModeConfig] {
    appState.orderedModeConfigs.filter { $0.slot.isRewriteCapable }
  }

  // MARK: - Re-run result / error

  @ViewBuilder
  private var rerunBlock: some View {
    if let rerunError {
      feedbackLine(
        text: rerunError, color: .orange, icon: "exclamationmark.triangle.fill")
    } else if let rerunResult {
      VStack(alignment: .leading, spacing: 4) {
        Text("neu (\(rerunModeName ?? "")) ✓".uppercased())
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.green)
        if let rerunFallbackNote {
          Text(rerunFallbackNote)
            .font(.system(size: 10.5))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(rerunResult)
          .font(.system(size: 11))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        Button("ergebnis kopieren") { copy(rerunResult, feedback: "ergebnis") }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
          .accessibilityLabel("Neues Ergebnis in die Zwischenablage")
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .tintBanner(.green, cornerRadius: 6)
    }
  }

  private func feedbackLine(text: String, color: Color, icon: String? = nil) -> some View {
    HStack(spacing: 4) {
      if let icon {
        Image(systemName: icon).font(.system(size: 9, weight: .semibold))
      }
      Text(text)
        .font(.system(size: 10))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(color)
  }

  // MARK: - Actions

  private func copy(_ text: String, feedback: String) {
    guard !text.isEmpty else { return }
    ArchiveClipboard.copyConcealed(text)
    copiedLabel = feedback
    Task {
      try? await Task.sleep(for: .seconds(Self.feedbackResetSeconds))
      if copiedLabel == feedback { copiedLabel = nil }
    }
  }

  private func rerun(as mode: ModeConfig) {
    guard !isRerunning else { return }
    isRerunning = true
    rerunResult = nil
    rerunError = nil
    rerunFallbackNote = nil
    let name = appState.displayName(for: mode)
    Task {
      let outcome = await appState.rerunRewrite(rawTranscript: entry.rawTranscript, as: mode.id)
      isRerunning = false
      switch outcome {
      case .success(let text):
        rerunModeName = name
        rerunResult = text
        // rerunRewrite set this on AppState during the run; surface it next to this result.
        rerunFallbackNote = appState.lastRewriteFallbackNote
      case .failure(let error):
        rerunError = error.localizedDescription
      }
    }
  }
}
