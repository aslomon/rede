#if !REDE_UPDATE_REHEARSAL
  #error("The rehearsal harness must never compile as production app code")
#endif

import AppKit
import Foundation

private let rehearsalMarker = "REDE_UPDATE_REHEARSAL_ONLY"

@main
@MainActor
private enum SparkleRehearsal {
  static func main() {
    let application = NSApplication.shared
    let delegate = RehearsalDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    application.run()
    withExtendedLifetime(delegate) {}
  }
}

@MainActor
private final class RehearsalDelegate: NSObject, NSApplicationDelegate {
  private var service: UpdateService?
  private var timer: Timer?
  private var previousStatus = ""
  private var requestedQuit = false
  private let start = Date()
  private let events = ProcessInfo.processInfo.environment["REDE_REHEARSAL_EVENT_FILE"]!
  private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "missing-version"

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard Bundle.main.bundleIdentifier?.hasPrefix("app.rede.rehearsal.") == true,
      Bundle.main.object(forInfoDictionaryKey: "REDEUpdateRehearsal") as? Bool == true,
      let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      let url = URL(string: feed), url.scheme == "http", url.host == "127.0.0.1"
    else { fatalError("Rehearsal requires its isolated bundle and loopback feed") }
    record("boot", extra: ["marker": rehearsalMarker, "bundle": Bundle.main.bundleIdentifier!])
    if version == "3" {
      record("newVersionLaunched")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
      return
    }
    UserDefaults.standard.set(true, forKey: "SUSendProfileInfo")
    service = UpdateService()
    record("profileDisabledBeforeStartup", extra: [
      "disabled": !UserDefaults.standard.bool(forKey: "SUSendProfileInfo")])
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
  }

  private func poll() {
    guard let service else { return }
    let current = String(describing: service.status)
    if current != previousStatus {
      previousStatus = current
      record("status", extra: ["state": current])
    }
    let downloads = Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool == true
    if case .staged = service.status, !requestedQuit {
      requestedQuit = true
      record("ordinaryQuitRequested")
      NSApp.terminate(nil)
    } else if !downloads, case .available = service.status, !requestedQuit {
      requestedQuit = true
      record("disabledDownloadsObservedAvailable")
      NSApp.terminate(nil)
    } else if Date().timeIntervalSince(start) > 45 {
      record("timeout")
      NSApp.terminate(nil)
    }
  }

  private func record(_ event: String, extra: [String: Any] = [:]) {
    var data = extra
    data["event"] = event
    data["version"] = version
    do {
      let line = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) + Data([10])
      if !FileManager.default.fileExists(atPath: events) {
        FileManager.default.createFile(atPath: events, contents: nil)
      }
      let file = try FileHandle(forWritingTo: URL(fileURLWithPath: events))
      try file.seekToEnd()
      try file.write(contentsOf: line)
      try file.close()
    } catch {
      fatalError("Cannot retain isolated rehearsal evidence: \(error)")
    }
  }
}
