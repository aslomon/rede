import Cocoa
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
  private var keyMonitor: Any?
  private var localKeyMonitor: Any?
  private var activeCombo: WorkflowType?  // Which combo is currently held

  var onHotkeyEvent: ((HotkeyEvent) -> Void)?

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
    // Escape aborts the current run. GLOBAL monitor: fires while another app is frontmost (the
    // background-hotkey case) — but it requires Accessibility/Input-Monitoring trust, so it's dead
    // when that grant is stale/missing (same root as paste).
    keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      Task { @MainActor in
        if event.keyCode == 53 {  // Escape
          self?.handleEscape()
        }
      }
    }
    // LOCAL monitor: covers the case where a Blitztext window (popover) is key — no Accessibility
    // needed. `handleEscape` no-ops when nothing is recording, so we always let the event propagate.
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {  // Escape
        Task { @MainActor in self?.handleEscape() }
      }
      return event
    }
  }

  func stop() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    globalMonitor = nil
    localMonitor = nil
    keyMonitor = nil
    localKeyMonitor = nil
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
