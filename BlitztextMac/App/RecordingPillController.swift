import AppKit
import SwiftUI
import os

private let pillLogger = Logger(subsystem: "app.blitztext.mac", category: "RecordingPill")

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
      model.accentColor = type.accentColorValue
      model.phase = .recording
      show()
    case .processing(let type):
      // Stay VISIBLE while transcribing/rewriting — the pill only disappears once the text is
      // inserted (.success) or the user cancels. It shows an indeterminate "working" animation.
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

  // MARK: - Panel lifecycle

  private func show() {
    if panel == nil {
      panel = makePanel()
    }
    guard let panel else {
      pillLogger.error("show(): panel is nil after makePanel()")
      return
    }
    positionPanel(panel)
    panel.orderFrontRegardless()
    startLevelTimer()
    pillLogger.debug(
      "show(): frame=\(NSStringFromRect(panel.frame), privacy: .public) visible=\(panel.isVisible) screens=\(NSScreen.screens.count)"
    )
  }

  private func hide() {
    stopLevelTimer()
    panel?.orderOut(nil)
  }

  private func makePanel() -> NSPanel {
    let hosting = NSHostingView(
      rootView: RecordingPillHostView(
        model: model,
        onStop: { [weak self] in self?.appState?.activeWorkflow?.stop() },
        onCancel: { [weak self] in self?.cancelCurrent() }
      )
    )
    hosting.translatesAutoresizingMaskIntoConstraints = false

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
    NSLayoutConstraint.activate([
      hosting.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hosting.topAnchor.constraint(equalTo: contentView.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])

    pillLogger.debug(
      "makePanel(): fitting=\(NSStringFromSize(fitting), privacy: .public) size=\(width)x\(height)")
    return panel
  }

  /// Centers the pill horizontally on the active screen, just below the top safe-area inset
  /// (so it tucks under the notch / menu bar). Falls back to `NSScreen.main` geometry.
  private func positionPanel(_ panel: NSPanel) {
    panel.layoutIfNeeded()
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
}

/// Observable bridge so the controller's timer-pushed `audioLevel`/`accentColor`/`phase` re-render.
@MainActor
final class RecordingPillModel: ObservableObject {
  @Published var audioLevel: Float = 0
  @Published var accentColor: Color = WorkflowType.transcription.accentColorValue
  @Published var phase: PillPhase = .recording
  /// Shown in the `.failed` state — the run's error message.
  @Published var errorMessage: String?
}

private struct RecordingPillHostView: View {
  @ObservedObject var model: RecordingPillModel
  let onStop: () -> Void
  let onCancel: () -> Void

  var body: some View {
    RecordingPillView(
      audioLevel: model.audioLevel,
      accentColor: model.accentColor,
      phase: model.phase,
      errorMessage: model.errorMessage,
      onStop: onStop,
      onCancel: onCancel
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
