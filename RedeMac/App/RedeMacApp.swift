import SwiftUI

@main
struct RedeMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private let menuBarStatusController = MenuBarStatusController()
  private var recordingPillController: RecordingPillController!
  private var localModelsWindowController: LocalModelsWindowController!
  private var archiveWindowController: ArchiveWindowController!
  private var onboardingWindowController: OnboardingWindowController!
  lazy var appState = AppState()

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !Self.isRunningUnitTests else { return }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    if let button = statusItem.button {
      menuBarStatusController.attach(to: button)
      button.action = #selector(togglePopover)
      button.target = self
    }

    popover = NSPopover()
    // Wider popover (was 340) so the 5 settings tabs + denser content read clearly.
    popover.contentSize = NSSize(width: 410, height: 500)
    popover.behavior = .transient
    popover.delegate = self
    popover.contentViewController = NSHostingController(rootView: MenuBarView(appState: appState))

    NSApp.setActivationPolicy(.accessory)

    // Hotkey events
    appState.hotkeyService.onHotkeyEvent = { [weak self] event in
      self?.handleHotkeyEvent(event)
    }
    // Escape only aborts (and is consumed) while a run is actually active.
    appState.hotkeyService.isAbortable = { [weak appState] in
      appState?.activeWorkflow?.phase.isActive ?? false
    }
    recordingPillController = RecordingPillController(appState: appState)
    localModelsWindowController = LocalModelsWindowController(
      appState: appState,
      manager: appState.localModelManager
    )
    archiveWindowController = ArchiveWindowController(appState: appState)
    onboardingWindowController = OnboardingWindowController(appState: appState) { [weak self] in
      self?.openSettingsInPopover()
    }
    appState.onMenuBarStatusChange = { [weak self] status in
      self?.menuBarStatusController.update(to: status)
      self?.recordingPillController.handleStatusChange(status)
    }
    appState.onCopyOnlyFallback = { [weak self] text in
      self?.recordingPillController.showCopyOnly(text)
    }
    appState.onVariantChoice = { [weak self] variants in
      self?.recordingPillController.showVariants(variants)
    }
    appState.hotkeyService.start()

    // Listen for popover dismiss requests (from auto-paste)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDismissPopover),
      name: .dismissPopover,
      object: nil
    )

    // Open the standalone "Lokale Modelle" management window on request from settings.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOpenLocalModelsWindow),
      name: .openLocalModelsWindow,
      object: nil
    )

    // Open the standalone "Transkriptions-Archiv" window on request from the archive tab.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOpenArchiveWindow),
      name: .openArchiveWindow,
      object: nil
    )

    // Open the standalone first-run onboarding wizard window (empty-state nudges, re-run action).
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOpenOnboardingWindow),
      name: .openOnboardingWindow,
      object: nil
    )

    DispatchQueue.main.async { [weak self] in
      self?.showOnboardingIfNeeded()
    }
  }

  @objc private func handleDismissPopover() {
    appState.isPopoverShown = false
    popover.performClose(nil)
  }

  @objc private func handleOpenLocalModelsWindow() {
    if popover.isShown {
      popover.performClose(nil)
      appState.isPopoverShown = false
    }
    localModelsWindowController.show()
  }

  @objc private func handleOpenArchiveWindow() {
    if popover.isShown {
      popover.performClose(nil)
      appState.isPopoverShown = false
    }
    archiveWindowController.show()
  }

  @objc private func handleOpenOnboardingWindow() {
    if popover.isShown {
      popover.performClose(nil)
      appState.isPopoverShown = false
    }
    onboardingWindowController.show()
  }

  /// Opens the popover already on the settings page — used by the wizard's "Zu den Einstellungen".
  private func openSettingsInPopover() {
    appState.prepareForPopoverPresentation()
    appState.openSettings()
    showPopover()
  }

  private func handleHotkeyEvent(_ event: HotkeyEvent) {
    switch event {
    case .down(let modeID):
      handleHotkeyDown(modeID)
    case .up(let modeID):
      handleHotkeyUp(modeID)
    case .cancel:
      handleHotkeyCancel()
    }
  }

  private func handleHotkeyDown(_ modeID: ModeConfig.ID) {
    guard appState.isConfigured else { return }

    let mode = appState.appSettings.hotkeyMode

    switch mode {
    case .hold:
      // Hold mode: start recording on key down
      appState.startMode(modeID, source: .hotkeyBackground)

    case .toggle:
      // Toggle mode: if already recording the same workflow, stop it. Otherwise record in the
      // BACKGROUND with the floating pill as the sole indicator — no popover, no waveform window.
      if let active = appState.activeWorkflow,
        appState.currentActiveModeID == modeID,
        active.phase.isActive
      {
        active.stop()
      } else {
        appState.startMode(modeID, source: .hotkeyBackground)
      }
    }
  }

  private func handleHotkeyUp(_ modeID: ModeConfig.ID) {
    let mode = appState.appSettings.hotkeyMode

    guard mode == .hold else { return }

    // Hold mode: stop recording on key release
    if let active = appState.activeWorkflow,
      appState.currentActiveModeID == modeID
    {
      // Only stop if currently recording (running phase)
      if case .running = active.phase {
        active.stop()
      }
    }
  }

  private func handleHotkeyCancel() {
    // ESC aborts (discards) the dictation — distinct from re-pressing the hotkey, which finishes it.
    // The pill flashes red and disappears.
    recordingPillController.cancelCurrent()
  }

  @objc private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
      appState.isPopoverShown = false
    } else {
      appState.prepareForPopoverPresentation()
      showPopover()
    }
  }

  private func showOnboardingIfNeeded() {
    guard appState.shouldShowOnboarding else { return }
    onboardingWindowController.show()
  }

  private func showPopover() {
    guard let button = statusItem.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    appState.isPopoverShown = true
    // Activate the app AND make the popover window key. Without makeKey(), an accessory
    // (LSUIElement) app shows the popover non-key: the first click only focuses it (you'd have to
    // click twice), the `.popover` material renders in its inactive shade until that click, and
    // `.transient` dismissal on an outside click is unreliable. Making it key fixes all three.
    NSApp.activate(ignoringOtherApps: true)
    popover.contentViewController?.view.window?.makeKey()
  }

  nonisolated func popoverDidClose(_ notification: Notification) {
    Task { @MainActor in
      appState.isPopoverShown = false
      switch appState.currentPhase {
      case .done, .error:
        appState.resetCurrentWorkflow()
      default:
        appState.page = .main
      }
    }
  }

  private static var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }
}
