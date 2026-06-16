import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermissionService {
  private static var hasPromptedThisSession = false

  // Monitoring state: fires `onChange` only on AXIsProcessTrusted() transitions.
  private static var monitorTimer: Timer?
  private static var workspaceObserver: NSObjectProtocol?
  private static var lastTrustedState: Bool?
  private static var changeHandler: ((Bool) -> Void)?

  static func currentStatus() -> Bool {
    AXIsProcessTrusted()
  }

  static func isTrusted(promptIfNeeded: Bool) -> Bool {
    let shouldPrompt = promptIfNeeded && !hasPromptedThisSession
    if shouldPrompt {
      hasPromptedThisSession = true
    }

    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt]
      as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func requestPermissionPrompt() -> Bool {
    hasPromptedThisSession = true
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Monitoring

  /// Starts observing the Accessibility trust state and invokes `onChange` only when
  /// `AXIsProcessTrusted()` actually transitions (not on every poll). Combines a workspace
  /// app-activation notification (cheap, catches the common "user toggled it then came back"
  /// case) with a low-frequency repeating timer as a safety net. Idempotent: calling it again
  /// replaces the previous handler.
  static func startMonitoring(onChange: @escaping (Bool) -> Void) {
    stopMonitoring()

    changeHandler = onChange
    lastTrustedState = AXIsProcessTrusted()

    let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
      Task { @MainActor in
        Self.evaluateTransition()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    monitorTimer = timer

    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        Self.evaluateTransition()
      }
    }
  }

  /// Stops all monitoring and releases the handler. Safe to call when not monitoring.
  static func stopMonitoring() {
    monitorTimer?.invalidate()
    monitorTimer = nil

    if let observer = workspaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      workspaceObserver = nil
    }

    changeHandler = nil
    lastTrustedState = nil
  }

  private static func evaluateTransition() {
    let current = AXIsProcessTrusted()
    guard current != lastTrustedState else { return }
    lastTrustedState = current
    changeHandler?(current)
  }
}
