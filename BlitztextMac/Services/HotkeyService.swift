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
  case down(ModeConfig.ID)  // Keys pressed
  case up(ModeConfig.ID)  // Keys released (for hold mode)
  case cancel  // Escape pressed
}

@Observable
@MainActor
final class HotkeyService {
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var escTap: CFMachPort?
  private var escTapSource: CFRunLoopSource?
  private var keyFallbackMonitor: Any?
  private var keyUpFallbackMonitor: Any?
  private var activeCombo: ModeConfig.ID?  // Which combo is currently held
  private var pressedKeyCodes = Set<UInt16>()
  private var hotkeyConfigs: [ModeConfig.ID: HotkeyConfig] = [:]

  var isSuspended = false {
    didSet {
      guard isSuspended else { return }
      activeCombo = nil
      pressedKeyCodes.removeAll()
    }
  }
  var onHotkeyEvent: ((HotkeyEvent) -> Void)?
  /// Set by the app: true while a run is active (so Escape should abort + be consumed). When false,
  /// Escape passes through untouched so it keeps working everywhere else.
  var isAbortable: (() -> Bool)?

  func reload(configs: [ModeConfig.ID: HotkeyConfig]) {
    hotkeyConfigs = configs
  }

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
    startKeyTap()
  }

  /// Escape-to-abort via a `CGEventTap`. Unlike `NSEvent.addGlobalMonitorForEvents(.keyDown)` (which
  /// needs the separate "Input Monitoring" right), a session event tap keys off the SAME Accessibility
  /// trust that paste already uses — so it works as soon as Accessibility is granted, no extra grant.
  /// It also CONSUMES Escape while a run is abortable, so the frontmost app doesn't act on it too.
  private func startKeyTap() {
    let mask =
      CGEventMask(1 << CGEventType.keyDown.rawValue)
      | CGEventMask(1 << CGEventType.keyUp.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
      return service.handleKeyTap(type: type, event: event)
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
      // a rede window is key). Once Accessibility is granted + the app relaunched, the tap is used.
      keyFallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
        [weak self] event in
        Task { @MainActor in
          if self?.isSuspended == true {
            return
          } else if event.keyCode == 53, self?.isAbortable?() ?? false {
            self?.handleEscape()
          } else { _ = self?.handleKeyDown(event) }
        }
        return event
      }
      keyUpFallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
        [weak self] event in
        Task { @MainActor in _ = self?.handleKeyUp(event.keyCode) }
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
  nonisolated private func handleKeyTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      MainActor.assumeIsolated {
        if let tap = self.escTap { CGEvent.tapEnable(tap: tap, enable: true) }
      }
      return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else {
      return Unmanaged.passUnretained(event)
    }
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    return MainActor.assumeIsolated {
      if self.isSuspended {
        return Unmanaged.passUnretained(event)
      }
      if type == .keyDown {
        if keyCode == 53, self.isAbortable?() ?? false {
          self.handleEscape()
          return nil
        }
        return self.handleKeyDown(keyCode: keyCode, modifiers: event.flags.hotkeyModifiers)
          ? nil
          : Unmanaged.passUnretained(event)
      }
      return self.handleKeyUp(keyCode) ? nil : Unmanaged.passUnretained(event)
    }
  }

  func stop() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let keyFallbackMonitor { NSEvent.removeMonitor(keyFallbackMonitor) }
    if let keyUpFallbackMonitor { NSEvent.removeMonitor(keyUpFallbackMonitor) }
    if let escTap, let escTapSource {
      CGEvent.tapEnable(tap: escTap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetMain(), escTapSource, .commonModes)
    }
    globalMonitor = nil
    localMonitor = nil
    keyFallbackMonitor = nil
    keyUpFallbackMonitor = nil
    escTap = nil
    escTapSource = nil
  }

  private func handleFlags(_ event: NSEvent) {
    guard !isSuspended else { return }
    let modifiers = event.modifierFlags.hotkeyModifiers
    if let combo = activeCombo, !activeComboMatchesCurrentModifiers(combo, modifiers: modifiers) {
      activeCombo = nil
      onHotkeyEvent?(.up(combo))
    }

    if !pressedKeyCodes.isEmpty {
      startMatchingComboIfNeeded(modifiers: modifiers)
      return
    }

    if let modeID = HotkeyRegistry.matchingModeID(
      modifiers: modifiers,
      keyCode: nil,
      keyCodes: [],
      configs: hotkeyConfigs
    ) {
      if activeCombo == nil {
        activeCombo = modeID
        onHotkeyEvent?(.down(modeID))
      }
      return
    }

    // Keys released -- fire up event
    if let combo = activeCombo {
      activeCombo = nil
      onHotkeyEvent?(.up(combo))
    }
  }

  @discardableResult
  private func handleKeyDown(_ event: NSEvent) -> Bool {
    handleKeyDown(keyCode: event.keyCode, modifiers: event.modifierFlags.hotkeyModifiers)
  }

  @discardableResult
  private func handleKeyDown(keyCode: UInt16, modifiers: [HotkeyModifier]) -> Bool {
    guard !isSuspended else { return false }
    pressedKeyCodes.insert(keyCode)

    if startMatchingComboIfNeeded(modifiers: modifiers) {
      return true
    }

    return HotkeyRegistry.hasPotentialMatch(
      modifiers: modifiers,
      keyCodes: Array(pressedKeyCodes),
      configs: hotkeyConfigs
    )
  }

  @discardableResult
  private func handleKeyUp(_ keyCode: UInt16) -> Bool {
    guard !isSuspended else { return false }
    pressedKeyCodes.remove(keyCode)
    guard
      let combo = activeCombo,
      hotkeyConfigs[combo]?.normalizedKeys.contains(where: { $0.keyCode == keyCode }) ?? false
    else {
      return false
    }
    activeCombo = nil
    onHotkeyEvent?(.up(combo))
    return true
  }

  private func handleEscape() {
    guard !isSuspended else { return }
    activeCombo = nil
    pressedKeyCodes.removeAll()
    onHotkeyEvent?(.cancel)
  }

  @discardableResult
  private func startMatchingComboIfNeeded(modifiers: [HotkeyModifier]) -> Bool {
    guard
      let modeID = HotkeyRegistry.matchingModeID(
        modifiers: modifiers,
        keyCodes: Array(pressedKeyCodes),
        configs: hotkeyConfigs
      )
    else {
      return false
    }

    if activeCombo == nil {
      activeCombo = modeID
      onHotkeyEvent?(.down(modeID))
    }
    return true
  }

  private func activeComboMatchesCurrentModifiers(
    _ modeID: ModeConfig.ID,
    modifiers: [HotkeyModifier]
  ) -> Bool {
    guard let config = hotkeyConfigs[modeID] else { return false }
    return Set(config.normalizedModifiers) == Set(modifiers)
  }
}
