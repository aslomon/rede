import AppKit
import SwiftUI

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
  private let model = RecordingPillModel()
  private var levelTimer: Timer?

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
      show()
    case .idle, .processing, .success, .error:
      hide()
    }
  }

  // MARK: - Panel lifecycle

  private func show() {
    if panel == nil {
      panel = makePanel()
    }
    guard let panel else { return }
    positionPanel(panel)
    panel.orderFrontRegardless()
    startLevelTimer()
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
        onCancel: { [weak self] in self?.appState?.resetCurrentWorkflow() }
      )
    )
    hosting.translatesAutoresizingMaskIntoConstraints = false

    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.onReturn = { [weak self] in self?.appState?.activeWorkflow?.stop() }
    panel.onEscape = { [weak self] in self?.appState?.resetCurrentWorkflow() }

    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    panel.isFloatingPanel = true
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovable = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.contentView = hosting

    return panel
  }

  /// Centers the pill horizontally on the active screen, just below the top safe-area inset
  /// (so it tucks under the notch / menu bar). Falls back to `NSScreen.main` geometry.
  private func positionPanel(_ panel: NSPanel) {
    panel.layoutIfNeeded()
    let fitting = panel.contentView?.fittingSize ?? NSSize(width: 160, height: 44)
    let width = max(fitting.width, 120)
    let height = max(fitting.height, 36)
    panel.setContentSize(NSSize(width: width, height: height))

    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame

    // visibleFrame.maxY already sits just below the menu bar (and the taller notch menu bar on
    // notched displays), so anchoring `topInset` below it tucks the pill under the notch area.
    let originX = visible.midX - (width / 2)
    let originY = visible.maxY - height - topInset

    panel.setFrameOrigin(NSPoint(x: originX, y: originY))
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

/// Observable bridge so the controller's timer-pushed `audioLevel`/`accentColor` re-render the view.
@MainActor
final class RecordingPillModel: ObservableObject {
  @Published var audioLevel: Float = 0
  @Published var accentColor: Color = WorkflowType.transcription.accentColorValue
}

private struct RecordingPillHostView: View {
  @ObservedObject var model: RecordingPillModel
  let onStop: () -> Void
  let onCancel: () -> Void

  var body: some View {
    RecordingPillView(
      audioLevel: model.audioLevel,
      accentColor: model.accentColor,
      onStop: onStop,
      onCancel: onCancel
    )
    .padding(6)
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
