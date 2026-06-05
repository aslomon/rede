import AVFoundation
import AppKit

/// Microphone authorization helper for the onboarding wizard. Mirrors the shape of
/// `AccessibilityPermissionService`: a synchronous status read, an async system-prompt request,
/// and a deep link into System Settings. Audio capture itself still runs through `AudioRecorder`;
/// this type only models the permission, never the recording.
@MainActor
enum MicrophonePermissionService {
  /// A coarse, UI-friendly mapping of `AVAuthorizationStatus` for the audio device.
  enum Status {
    case granted
    case denied
    case notDetermined

    var isGranted: Bool { self == .granted }
  }

  /// The current microphone authorization, read synchronously. `.restricted` is folded into
  /// `.denied` because the user-facing remedy (open System Settings) is identical.
  static var currentStatus: Status {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return .granted
    case .notDetermined:
      return .notDetermined
    case .denied, .restricted:
      return .denied
    @unknown default:
      return .denied
    }
  }

  /// Triggers the system microphone prompt (only effective while the status is `.notDetermined`)
  /// and returns the resulting authorization. Safe to call repeatedly.
  static func request() async -> Status {
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    return granted ? .granted : currentStatus
  }

  /// Opens the Privacy → Microphone pane in System Settings so a previously-denied grant can be
  /// flipped on by hand (the system prompt only ever appears once).
  static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
