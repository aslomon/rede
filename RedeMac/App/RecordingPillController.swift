import AppKit
import SwiftUI
import os

private let pillLogger = Logger(subsystem: "app.rede.mac", category: "RecordingPill")

/// Drives the floating recording pill. Created by `AppDelegate`, it shows a borderless,
/// non-activating panel at the top-center of the active screen while a workflow is RECORDING
/// and hides it as soon as recording stops (processing/done/error/idle).
///
/// The panel never steals focus from the user's frontmost app (`.nonactivatingPanel`,
/// `becomesKeyOnlyIfNeeded`), so dictation-into-other-apps keeps working. A lightweight timer
/// pushes the live `audioLevel` into the hosted SwiftUI view so the waveform stays alive.
@MainActor
final class RecordingPillController {
  private weak var appState: AppState?
  private var panel: NSPanel?
  /// The hosting view inside the panel — kept so `positionPanel` reads its fitting size directly
  /// rather than guessing via `contentView.subviews.first`. Owned by the panel's contentView.
  private weak var hostingView: NSView?
  private let model = RecordingPillModel()
  private var levelTimer: Timer?
  /// True while the red cancel/error flash is playing, so the trailing `.idle` doesn't hide early.
  private var isFlashing = false
  private var flashTask: Task<Void, Never>?
  private var busyNoticeTask: Task<Void, Never>?

  /// Distance below the top of the active screen's safe area (under the notch / menu bar).
  private let topInset: CGFloat = 8

  init(appState: AppState) {
    self.appState = appState
  }

  // MARK: - Status-driven show/hide

  /// Called from `AppDelegate` whenever `menuBarStatus` changes.
  func handleStatusChange(_ status: MenuBarStatus) {
    switch status {
    case .recording(let type):
      // A new run supersedes any lingering cancel/error/copy-only card (and its pending hide timer).
      cancelTransientState()
      model.accentColor = type.accentColorValue
      model.phase = .recording
      show()
    case .processing(let type):
      // Stay VISIBLE while transcribing/rewriting — the pill only disappears once the text is
      // inserted (.success) or the user cancels. It shows an indeterminate "working" animation.
      cancelTransientState()
      model.accentColor = type.accentColorValue
      model.phase = .processing
      show()
    case .success:
      // Text was inserted → done.
      hide()
    case .error:
      // Surface the actual error message — crucial for background-hotkey runs, which otherwise
      // show only a silent red status with no explanation of WHY the dictation failed.
      flashErrorAndHide(message: appState?.lastRunErrorMessage)
    case .idle:
      // Ignore the .idle that arrives right after a cancel — the flash owns the hide.
      if !isFlashing { hide() }
    }
  }

  /// Cancel (discard) the active dictation — used by ESC, the pill's ✕, and the panel's Esc.
  /// Resets the workflow and flashes the pill red before hiding. No-op when nothing is active.
  func cancelCurrent() {
    guard appState?.activeWorkflow != nil else { return }
    // Start the flash FIRST (sets isFlashing) so the `.idle` from resetCurrentWorkflow is ignored.
    flashCancelAndHide()
    appState?.resetCurrentWorkflow()
  }

  /// Briefly tints the pill red (user cancel) and then hides it. Only flashes when the pill is
  /// already on screen — a pre-recording error (e.g. empty selection) just hides without a flash.
  private func flashCancelAndHide() {
    guard panel?.isVisible == true else {
      hide()
      return
    }
    isFlashing = true
    model.phase = .cancelled
    stopLevelTimer()
    flashTask?.cancel()
    flashTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(550))
      guard let self else { return }
      self.isFlashing = false
      self.panel?.orderOut(nil)
    }
  }

  /// Shows the failure as a red pill WITH the error message for a few seconds, then hides. Unlike
  /// the cancel flash this creates the panel if needed (so even a pre-recording error is visible)
  /// and stays long enough to read. Falls back to the brief cancel flash when there is no message.
  private func flashErrorAndHide(message: String?) {
    let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !text.isEmpty else {
      flashCancelAndHide()
      return
    }
    if panel == nil { panel = makePanel() }
    guard let panel else {
      hide()
      return
    }
    isFlashing = true
    model.errorMessage = text
    model.phase = .failed
    stopLevelTimer()
    flashTask?.cancel()
    flashTask = Task { @MainActor [weak self] in
      guard let self else { return }
      // Let SwiftUI lay out the wider error content, then resize + recenter the panel to fit it.
      try? await Task.sleep(for: .milliseconds(30))
      self.positionPanel(panel)
      panel.orderFrontRegardless()
      try? await Task.sleep(for: .milliseconds(4200))
      guard !Task.isCancelled else { return }
      self.isFlashing = false
      self.model.errorMessage = nil
      panel.orderOut(nil)
    }
  }

  // MARK: - Copy-only fallback

  /// Expands the pill into a card showing the dictated text the app could NOT auto-paste, with a
  /// Copy action. Stays ~18s (long enough to read/copy) or until dismissed; the text also remains on
  /// the clipboard so ⌘V works regardless.
  func showCopyOnly(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if panel == nil { panel = makePanel() }
    guard let panel else { return }
    isFlashing = true  // protect from a trailing `.idle` hide
    model.copyOnlyText = trimmed
    model.phase = .copyOnly
    stopLevelTimer()
    flashTask?.cancel()
    flashTask = Task { @MainActor [weak self] in
      guard let self else { return }
      // Let SwiftUI lay out the much larger card, then size + recenter the panel to fit it.
      try? await Task.sleep(for: .milliseconds(30))
      self.positionPanel(panel)
      panel.orderFrontRegardless()
      try? await Task.sleep(for: .seconds(18))
      guard !Task.isCancelled, self.model.phase == .copyOnly else { return }
      self.dismissCopyOnly()
    }
  }

  func showVariants(_ variants: PendingRewriteVariants) {
    guard variants.variants.count > 1 else { return }
    if panel == nil { panel = makePanel() }
    guard let panel else { return }
    isFlashing = true
    model.pendingVariants = variants
    model.phase = .variantChoice
    stopLevelTimer()
    flashTask?.cancel()
    flashTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .milliseconds(30))
      self.positionPanel(panel)
      panel.orderFrontRegardless()
    }
  }

  func showWorkflowStartBlocked(_ message: String) {
    let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    if panel == nil { panel = makePanel() }
    guard let panel else { return }

    model.busyNotice = text
    if panel.isVisible {
      positionPanel(panel)
    } else {
      show()
    }

    busyNoticeTask?.cancel()
    busyNoticeTask = Task { @MainActor [weak self, weak panel] in
      try? await Task.sleep(for: .seconds(1.1))
      guard let self, !Task.isCancelled else { return }
      if self.model.busyNotice == text {
        self.model.busyNotice = nil
        if let panel { self.positionPanel(panel) }
      }
    }
  }

  private func dismissCopyOnly() {
    flashTask?.cancel()
    isFlashing = false
    model.copyOnlyText = nil
    panel?.orderOut(nil)
  }

  private func dismissVariantChoiceCard() {
    flashTask?.cancel()
    isFlashing = false
    model.pendingVariants = nil
    panel?.orderOut(nil)
  }

  private func dismissCurrentCard() {
    if model.phase == .variantChoice {
      dismissVariantChoiceCard()
      appState?.dismissVariantChoice()
    } else {
      dismissCopyOnly()
    }
  }

  /// Clears any lingering transient card (cancel flash / error / copy-only) and its pending hide
  /// timer so a NEW run can take over the pill cleanly without an old timer ordering it out.
  private func cancelTransientState() {
    flashTask?.cancel()
    flashTask = nil
    busyNoticeTask?.cancel()
    busyNoticeTask = nil
    isFlashing = false
    model.errorMessage = nil
    model.busyNotice = nil
    model.copyOnlyText = nil
    model.pendingVariants = nil
  }

  private func copyTextToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  // MARK: - Panel lifecycle

  private func show() {
    if panel == nil {
      panel = makePanel()
    }
    guard let panel else {
      pillLogger.error("show(): panel is nil after makePanel()")
      return
    }
    // Order in FIRST so `panel.screen` is non-nil, THEN position — otherwise the very first show
    // falls back to NSScreen.main geometry and can land off-center on a secondary/active display.
    panel.orderFrontRegardless()
    positionPanel(panel)
    startLevelTimer()
    pillLogger.debug(
      "show(): frame=\(NSStringFromRect(panel.frame), privacy: .public) visible=\(panel.isVisible) screens=\(NSScreen.screens.count)"
    )
  }

  private func hide() {
    stopLevelTimer()
    busyNoticeTask?.cancel()
    busyNoticeTask = nil
    model.busyNotice = nil
    panel?.orderOut(nil)
  }

  private func makePanel() -> NSPanel {
    let hosting = NSHostingView(
      rootView: RecordingPillHostView(
        model: model,
        onStop: { [weak self] in self?.appState?.activeWorkflow?.stop() },
        onCancel: { [weak self] in self?.cancelCurrent() },
        onCopy: { [weak self] text in self?.copyTextToPasteboard(text) },
        onChooseVariant: { [weak self] variantID in
          self?.dismissVariantChoiceCard()
          self?.appState?.chooseVariant(variantID)
        },
        onCopyVariant: { [weak self] variantID in
          self?.dismissVariantChoiceCard()
          self?.appState?.copyVariant(variantID)
        },
        onDismiss: { [weak self] in self?.dismissCurrentCard() }
      )
    )
    hosting.translatesAutoresizingMaskIntoConstraints = false
    // Report a stable NATURAL size so the panel can be sized + centered correctly (a both-direction
    // edge pin makes fittingSize echo the locked frame width → off-center pill).
    hosting.sizingOptions = [.intrinsicContentSize]

    // Derive a concrete size from SwiftUI so the panel is never zero-sized.
    let fitting = hosting.fittingSize
    let width = max(fitting.width, 160)
    let height = max(fitting.height, 44)

    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.onReturn = { [weak self] in self?.appState?.activeWorkflow?.stop() }
    panel.onEscape = { [weak self] in self?.cancelCurrent() }

    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    panel.isFloatingPanel = true
    // No AppKit window shadow: it draws a rectangular box around the transparent panel. The
    // capsule's own SwiftUI `.shadow` (shaped, with padding room) is the only shadow.
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovable = false
    panel.backgroundColor = .clear
    panel.isOpaque = false

    // Pin the hosting view to the contentView so it always fills (and is sized by) the panel.
    // (Setting `contentView = hosting` with TAMIC off + no constraints collapsed it to zero before.)
    guard let contentView = panel.contentView else {
      pillLogger.error("makePanel(): panel.contentView is nil")
      return panel
    }
    contentView.addSubview(hosting)
    hostingView = hosting
    // Pin only leading+top and let the host's intrinsic size drive width/height (the panel is then
    // sized to `hosting.fittingSize` in `positionPanel`). Pinning all four edges locked the width and
    // poisoned `fittingSize`, so the centering math used a stale width → the pill drifted off-center.
    NSLayoutConstraint.activate([
      hosting.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hosting.topAnchor.constraint(equalTo: contentView.topAnchor),
    ])

    pillLogger.debug(
      "makePanel(): fitting=\(NSStringFromSize(fitting), privacy: .public) size=\(width)x\(height)")
    return panel
  }

  /// Centers the pill horizontally on the active screen, just below the top safe-area inset
  /// (so it tucks under the notch / menu bar). Falls back to `NSScreen.main` geometry.
  private func positionPanel(_ panel: NSPanel) {
    panel.layoutIfNeeded()
    // Force the SwiftUI subtree to re-measure so `fittingSize` reflects the CURRENT content (e.g.
    // after switching to the wide `.failed`/`.copyOnly` cards), not a stale size.
    hostingView?.layoutSubtreeIfNeeded()
    let fitting =
      hostingView?.fittingSize
      ?? panel.contentView?.fittingSize
      ?? NSSize(width: 160, height: 44)
    let width = max(fitting.width, 160)
    let height = max(fitting.height, 44)

    // `panel.screen` is nil until first ordered in; fall back to main / first screen.
    let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else {
      pillLogger.error("positionPanel(): no screen available")
      panel.setContentSize(NSSize(width: width, height: height))
      return
    }
    let visible = screen.visibleFrame

    // visibleFrame.maxY already sits just below the menu bar (and the taller notch menu bar on
    // notched displays), so anchoring `topInset` below it tucks the pill under the notch area.
    let originX = visible.midX - (width / 2)
    let originY = visible.maxY - height - topInset

    panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
    pillLogger.debug(
      "positionPanel(): frame=\(NSStringFromRect(panel.frame), privacy: .public)")
  }

  // MARK: - Live level pump

  private func startLevelTimer() {
    guard levelTimer == nil else { return }
    // 30 Hz keeps the waveform smooth without burning cycles; WaveformView interpolates jitter.
    levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let workflow = self.appState?.activeWorkflow else { return }
        self.model.audioLevel = workflow.audioLevel
      }
    }
    if let levelTimer {
      RunLoop.main.add(levelTimer, forMode: .common)
    }
  }

  private func stopLevelTimer() {
    levelTimer?.invalidate()
    levelTimer = nil
  }

  deinit {
    levelTimer?.invalidate()
  }
}

// MARK: - Hosted SwiftUI bridge

/// The pill's visual phase: live recording, working (transcribing/rewriting), a brief cancel flash,
/// or a `failed` state that shows the actual error MESSAGE (so a background-hotkey run that fails is
/// no longer just a silent red — the user sees WHY).
enum PillPhase {
  case recording
  case processing
  case cancelled
  case failed
  /// Auto-paste could not land — the pill expands into a scrollable card showing the dictated text
  /// with a Copy action, so the result is never silently stuck on the clipboard.
  case copyOnly
  case variantChoice
}

/// Observable bridge so the controller's timer-pushed `audioLevel`/`accentColor`/`phase` re-render.
@MainActor
final class RecordingPillModel: ObservableObject {
  @Published var audioLevel: Float = 0
  @Published var accentColor: Color = WorkflowType.transcription.accentColorValue
  @Published var phase: PillPhase = .recording
  /// Shown in the `.failed` state — the run's error message.
  @Published var errorMessage: String?
  @Published var busyNotice: String?
  /// Shown in the `.copyOnly` state — the dictated text the user can read/copy.
  @Published var copyOnlyText: String?
  @Published var pendingVariants: PendingRewriteVariants?
}

private struct RecordingPillHostView: View {
  @ObservedObject var model: RecordingPillModel
  let onStop: () -> Void
  let onCancel: () -> Void
  let onCopy: (String) -> Void
  let onChooseVariant: (RewriteVariant.ID) -> Void
  let onCopyVariant: (RewriteVariant.ID) -> Void
  let onDismiss: () -> Void

  var body: some View {
    RecordingPillView(
      audioLevel: model.audioLevel,
      accentColor: model.accentColor,
      phase: model.phase,
      errorMessage: model.errorMessage,
      busyNotice: model.busyNotice,
      copyOnlyText: model.copyOnlyText,
      pendingVariants: model.pendingVariants,
      onStop: onStop,
      onCancel: onCancel,
      onCopy: onCopy,
      onChooseVariant: onChooseVariant,
      onCopyVariant: onCopyVariant,
      onDismiss: onDismiss
    )
    // Margin around the capsule so its soft `.shadow` (radius 8) is never clipped by the panel
    // edge into a hard rectangle.
    .padding(12)
  }
}

// MARK: - Key-handling panel

/// A borderless, non-activating panel that can still become key when clicked so the local
/// Return/Escape handlers work. Because it is non-activating it never grabs focus on show;
/// the handlers only fire if the user has actually interacted with the pill. The existing
/// global Esc-cancel hotkey is unaffected.
private final class KeyablePanel: NSPanel {
  var onReturn: (() -> Void)?
  var onEscape: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76:  // Return, keypad Enter
      onReturn?()
    case 53:  // Escape
      onEscape?()
    default:
      super.keyDown(with: event)
    }
  }
}
