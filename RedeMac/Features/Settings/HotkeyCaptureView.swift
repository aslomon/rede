import AppKit
import SwiftUI

struct HotkeyCapture {
  var modifiers: [HotkeyModifier]
  var keys: [HotkeyKeyBinding]

  static let empty = HotkeyCapture(modifiers: [], keys: [])

  var normalizedModifiers: [HotkeyModifier] {
    let selected = Set(modifiers)
    return HotkeyModifier.displayOrder.filter { selected.contains($0) }
  }

  var normalizedKeys: [HotkeyKeyBinding] {
    var seen = Set<UInt16>()
    var result: [HotkeyKeyBinding] = []
    for key in keys.sorted(by: { $0.keyCode < $1.keyCode }) {
      guard !seen.contains(key.keyCode) else { continue }
      seen.insert(key.keyCode)
      result.append(key)
    }
    return result
  }

  var labelParts: [String] {
    normalizedModifiers.map(\.label) + normalizedKeys.map(\.keyLabel)
  }

  var isConfigured: Bool {
    !normalizedModifiers.isEmpty || !normalizedKeys.isEmpty
  }
}

struct HotkeyCaptureView: NSViewRepresentable {
  @Binding var isRecording: Bool
  let onChange: (HotkeyCapture) -> Void
  let onCapture: (HotkeyCapture) -> Void

  func makeNSView(context: Context) -> CaptureNSView {
    let view = CaptureNSView()
    view.onChange = onChange
    view.onCapture = onCapture
    view.onCancel = { isRecording = false }
    return view
  }

  func updateNSView(_ nsView: CaptureNSView, context: Context) {
    nsView.onChange = onChange
    nsView.onCapture = { capture in
      onCapture(capture)
      isRecording = false
    }
    nsView.onCancel = {
      nsView.resetCapture()
      isRecording = false
    }
    nsView.setRecording(isRecording)
    if isRecording {
      DispatchQueue.main.async {
        nsView.window?.makeFirstResponder(nsView)
      }
    }
  }

  final class CaptureNSView: NSView {
    var isRecording = false
    var onChange: (HotkeyCapture) -> Void = { _ in }
    var onCapture: (HotkeyCapture) -> Void = { _ in }
    var onCancel: () -> Void = {}
    private var capturedModifiers: [HotkeyModifier] = []
    private var pressedKeys: [UInt16: HotkeyKeyBinding] = [:]
    private var capturedKeys: [UInt16: HotkeyKeyBinding] = [:]

    override var acceptsFirstResponder: Bool { true }

    func setRecording(_ value: Bool) {
      guard isRecording != value else { return }
      isRecording = value
      resetCapture()
    }

    override func flagsChanged(with event: NSEvent) {
      guard isRecording else {
        super.flagsChanged(with: event)
        return
      }
      mergeModifiers(event.modifierFlags.hotkeyModifiers)
      onChange(currentCapture())
    }

    override func keyDown(with event: NSEvent) {
      guard isRecording else {
        super.keyDown(with: event)
        return
      }
      if event.keyCode == 53 {
        resetCapture()
        onCancel()
        return
      }
      guard !event.isARepeat else { return }
      mergeModifiers(event.modifierFlags.hotkeyModifiers)
      let binding = HotkeyKeyBinding(
        keyCode: event.keyCode,
        keyLabel: HotkeyKey.label(
          keyCode: event.keyCode,
          characters: event.charactersIgnoringModifiers
        )
      )
      pressedKeys[event.keyCode] = binding
      capturedKeys[event.keyCode] = binding
      onChange(currentCapture())
    }

    override func keyUp(with event: NSEvent) {
      guard isRecording else {
        super.keyUp(with: event)
        return
      }
      mergeModifiers(event.modifierFlags.hotkeyModifiers)
      pressedKeys.removeValue(forKey: event.keyCode)
      onChange(currentCapture())
    }

    func finishCapture() {
      let capture = currentCapture()
      resetCapture()
      guard capture.isConfigured else { return }
      onCapture(capture)
    }

    func resetCapture() {
      capturedModifiers = []
      pressedKeys = [:]
      capturedKeys = [:]
      onChange(.empty)
    }

    private func currentCapture() -> HotkeyCapture {
      HotkeyCapture(
        modifiers: capturedModifiers,
        keys: capturedKeys.values.sorted { $0.keyCode < $1.keyCode }
      )
    }

    private func mergeModifiers(_ modifiers: [HotkeyModifier]) {
      let merged = Set(capturedModifiers).union(modifiers)
      capturedModifiers = HotkeyModifier.displayOrder.filter { merged.contains($0) }
    }
  }
}
