import Cocoa
import CoreGraphics
import Observation

enum HotkeyMode: String, Codable, Sendable, CaseIterable, Identifiable {
  case hold  // Tasten halten = aufnehmen, loslassen = stoppen
  case toggle  // Einmal drücken = starten, nochmal/Escape = stoppen

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .hold: return "Halten"
    case .toggle: return "Drücken"
    }
  }

  var description: String {
    switch self {
    case .hold: return "Tasten halten zum Aufnehmen, loslassen zum Stoppen"
    case .toggle: return "Einmal drücken zum Starten, nochmal oder Escape zum Stoppen"
    }
  }
}

enum HotkeyEvent {
  case down(WorkflowType)  // Keys pressed
  case up(WorkflowType)  // Keys released (for hold mode)
  case cancel  // Escape pressed
}

@Observable
@MainActor
final class HotkeyService {
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var escTap: CFMachPort?
  private var escTapSource: CFRunLoopSource?
  private var escFallbackMonitor: Any?
  private var activeCombo: WorkflowType?  // Which combo is currently held

  var onHotkeyEvent: ((HotkeyEvent) -> Void)?
  /// Set by the app: true while a run is active (so Escape should abort + be consumed). When false,
  /// Escape passes through untouched so it keeps working everywhere else.
  var isAbortable: (() -> Bool)?

  func start() {
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      Task { @MainActor in
        self?.handleFlags(event)
      }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      Task { @MainActor in
        self?.handleFlags(event)
      }
      return event
    }
    startEscTap()
  }

  /// Escape-to-abort via a `CGEventTap`. Unlike `NSEvent.addGlobalMonitorForEvents(.keyDown)` (which
  /// needs the separate "Input Monitoring" right), a session event tap keys off the SAME Accessibility
  /// trust that paste already uses — so it works as soon as Accessibility is granted, no extra grant.
  /// It also CONSUMES Escape while a run is abortable, so the frontmost app doesn't act on it too.
  private func startEscTap() {
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
      return service.handleEscTap(type: type, event: event)
    }

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      // No Accessibility trust yet → fall back to a LOCAL keyDown monitor (covers only the case where
      // a Blitztext window is key). Once Accessibility is granted + the app relaunched, the tap is used.
      escFallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
        [weak self] event in
        if event.keyCode == 53 { Task { @MainActor in self?.handleEscape() } }
        return event
      }
      return
    }

    escTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    escTapSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  /// Tap callback body. Runs on the MAIN run loop (the source is added there), so MainActor state is
  /// reachable via `assumeIsolated`. Returns nil to CONSUME the event, or the event to pass it on.
  nonisolated private func handleEscTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      MainActor.assumeIsolated {
        if let tap = self.escTap { CGEvent.tapEnable(tap: tap, enable: true) }
      }
      return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 else {
      return Unmanaged.passUnretained(event)
    }
    return MainActor.assumeIsolated {
      guard self.isAbortable?() ?? false else {
        return Unmanaged.passUnretained(event)  // nothing to abort → let Escape work normally
      }
      self.handleEscape()
      return nil  // consume — the frontmost app does not also receive this Escape
    }
  }

  func stop() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let escFallbackMonitor { NSEvent.removeMonitor(escFallbackMonitor) }
    if let escTap, let escTapSource {
      CGEvent.tapEnable(tap: escTap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetMain(), escTapSource, .commonModes)
    }
    globalMonitor = nil
    localMonitor = nil
    escFallbackMonitor = nil
    escTap = nil
    escTapSource = nil
  }

  private func handleFlags(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    // fn + Shift + Control -> local transcription
    if flags == [.function, .shift, .control] {
      if activeCombo == nil {
        activeCombo = .localTranscription
        onHotkeyEvent?(.down(.localTranscription))
      }
      return
    }

    // fn + Shift -> transcription
    if flags == [.function, .shift] {
      if activeCombo == nil {
        activeCombo = .transcription
        onHotkeyEvent?(.down(.transcription))
      }
      return
    }

    // fn + Control -> Textverbesserer
    if flags == [.function, .control] {
      if activeCombo == nil {
        activeCombo = .textImprover
        onHotkeyEvent?(.down(.textImprover))
      }
      return
    }

    // fn + Option -> Rage Mode
    if flags == [.function, .option] {
      if activeCombo == nil {
        activeCombo = .dampfAblassen
        onHotkeyEvent?(.down(.dampfAblassen))
      }
      return
    }

    // fn + Command -> Emoji Mode
    if flags == [.function, .command] {
      if activeCombo == nil {
        activeCombo = .emojiText
        onHotkeyEvent?(.down(.emojiText))
      }
      return
    }

    // Keys released -- fire up event
    if let combo = activeCombo {
      activeCombo = nil
      onHotkeyEvent?(.up(combo))
    }
  }

  private func handleEscape() {
    activeCombo = nil
    onHotkeyEvent?(.cancel)
  }
}
