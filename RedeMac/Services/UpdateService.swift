import Foundation
import Observation
import os

#if SPARKLE_ENABLED
  import Sparkle
#endif

@MainActor
protocol UpdatePreferences: AnyObject {
  var automaticallyChecksForUpdates: Bool { get set }
  var automaticallyDownloadsUpdates: Bool { get set }
  var sendsSystemProfile: Bool { get set }
  var lastUpdateCheckDate: Date? { get }
  var canCheckForUpdates: Bool { get }
}

#if SPARKLE_ENABLED
  extension SPUUpdater: UpdatePreferences {}
#endif

/// Wraps the Sparkle updater behind a small app-facing service (pattern: `LaunchAtLoginService`).
/// All Sparkle types stay behind `SPARKLE_ENABLED` so a Mac App Store build can compile the
/// framework out entirely (stores forbid self-updating apps) without touching any call sites.
///
/// Privacy: daily checks fetch the public appcast over HTTPS; enabled automatic downloads also
/// fetch signed release archives. Requests carry standard HTTP metadata and the app version.
/// Sparkle's system profiling stays disabled. See docs/privacy.md.
@Observable
@MainActor
final class UpdateService: NSObject {
  /// Whether this build contains the updater at all. A Mac App Store variant compiles Sparkle out;
  /// UI gates entire update surfaces on this so the MAS build shows nothing to configure.
  nonisolated static var isAvailable: Bool {
    #if SPARKLE_ENABLED
      return true
    #else
      return false
    #endif
  }

  /// Mirrors `SPUUpdater.canCheckForUpdates`: false while an update session is already running.
  private(set) var canCheckForUpdates = false
  private(set) var lastUpdateCheckDate: Date?
  /// Set while a gentle update reminder is pending: the display version users can install.
  /// Drives the quiet popover hint instead of a focus-stealing alert (LSUIElement app).
  private(set) var availableUpdateVersion: String?
  /// Stored mirror of Sparkle's `automaticallyChecksForUpdates` so `@Observable` change tracking
  /// works (computed passthroughs would not notify SwiftUI). Kept in sync via `refresh()`.
  private(set) var automaticChecksEnabled = false
  private(set) var automaticDownloadsEnabled = false
  private(set) var status: Status = .idle(lastChecked: nil)
  var isBusy: @MainActor () -> Bool = { false } {
    didSet { busyStateDidChange() }
  }
  @ObservationIgnored private var stagedInstallation: (() -> Void)?
  @ObservationIgnored private var invokingStagedInstallation = false
  @ObservationIgnored private var deferredRelaunch: (() -> Void)?
  @ObservationIgnored private var busyObservationGeneration = 0

  private let logger = Logger(subsystem: "app.rede.mac", category: "Updates")
  @ObservationIgnored private var preferences: (any UpdatePreferences)?

  #if SPARKLE_ENABLED
    private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var updaterObservations: [NSKeyValueObservation] = []
  #endif

  override init() {
    super.init()
    #if SPARKLE_ENABLED
      // Hosted tests construct AppState; keep their normal startup away from real preferences.
      if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
         NSClassFromString("XCTestCase") != nil {
        logger.debug("Updater startup skipped in app-hosted XCTest; Sparkle preferences untouched")
        return
      }
      let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
      )
      updaterController = controller
      preferences = controller.updater
      configureAndStartUpdater { controller.startUpdater() }
    #endif
  }

  init(preferences: any UpdatePreferences, startUpdater: () -> Void = {}) {
    self.preferences = preferences
    super.init()
    configureAndStartUpdater(startUpdater)
  }

  private func configureAndStartUpdater(_ startUpdater: () -> Void) {
    preferences?.sendsSystemProfile = false
    #if SPARKLE_ENABLED
      if let updater = preferences as? SPUUpdater { observeUpdater(updater) }
    #endif
    startUpdater()
    refresh()
  }

  #if SPARKLE_ENABLED
    private func observeUpdater(_ updater: SPUUpdater) {
      // Sparkle may change these through its own dialogs as well as the app's settings.
      let refreshState: () -> Void = { [weak self] in
        Task { @MainActor [weak self] in self?.refresh() }
      }
      updaterObservations = [
        updater.observe(\.canCheckForUpdates, options: [.initial]) { _, _ in
          refreshState()
        },
        updater.observe(\.automaticallyChecksForUpdates) { _, _ in
          refreshState()
        },
        updater.observe(\.automaticallyDownloadsUpdates) { _, _ in
          refreshState()
        },
        updater.observe(\.lastUpdateCheckDate) { _, _ in
          refreshState()
        }
      ]
    }
  #endif

  /// User-initiated check — shows Sparkle's standard UI (progress, release notes, install).
  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    switch status {
    case .staged, .downloading: return
    default: break
    }
    status = .checking
    #if SPARKLE_ENABLED
      availableUpdateVersion = nil
      updaterController?.checkForUpdates(nil)
    #endif
  }

  func setAutomaticChecksEnabled(_ enabled: Bool) {
    preferences?.automaticallyChecksForUpdates = enabled
    refresh()
  }

  func setAutomaticDownloadsEnabled(_ enabled: Bool) {
    preferences?.automaticallyDownloadsUpdates = enabled
    refresh()
  }

  func refresh() {
    guard let preferences else { return }
    automaticChecksEnabled = preferences.automaticallyChecksForUpdates
    automaticDownloadsEnabled = preferences.automaticallyDownloadsUpdates
    lastUpdateCheckDate = preferences.lastUpdateCheckDate
    canCheckForUpdates = preferences.canCheckForUpdates
    if case .idle = status { status = .idle(lastChecked: lastUpdateCheckDate) }
  }

  func checkNow() { checkForUpdates() }

  func busyStateDidChange() {
    busyObservationGeneration += 1
    guard deferredRelaunch != nil else { return }
    let generation = busyObservationGeneration
    let busy = isBusy
    let currentlyBusy = withObservationTracking { busy() } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.busyObservationGeneration == generation else { return }
        self.busyStateDidChange()
      }
    }
    guard !currentlyBusy, let action = deferredRelaunch else { return }
    deferredRelaunch = nil
    busyObservationGeneration += 1
    action()
  }

  @discardableResult
  func installStagedUpdateNow() -> Bool {
    guard !isBusy(), !invokingStagedInstallation, let install = stagedInstallation else { return false }
    invokingStagedInstallation = true
    defer { invokingStagedInstallation = false }
    install()
    return true
  }

  func stageInstallation(version: String, install: @escaping () -> Void) {
    stagedInstallation = install
    availableUpdateVersion = version
    status = .staged(version: version)
  }

  func postponeRelaunchIfBusy(version: String, install: @escaping () -> Void) -> Bool {
    guard isBusy() else { return false }
    deferredRelaunch = install
    status = .staged(version: version)
    busyStateDidChange()
    return true
  }

  func shouldShowScheduledUpdate(immediateFocus: Bool) -> Bool {
    immediateFocus && !isBusy()
  }

  func foundUpdate(version: String) {
    availableUpdateVersion = version
    status = .available(version: version)
  }

  func startedDownload() { status = .downloading(fraction: nil) }
  func clearUpdateReminder() { availableUpdateVersion = nil }

  func finishedUpdateCycle(error: Error?) {
    refresh()
    if let error {
      let failure = error as NSError
      let normal = (failure.domain == "SUSparkleErrorDomain" && [1001, 4007, 4008].contains(failure.code))
        || (failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError)
      if !normal {
        stagedInstallation = nil
        deferredRelaunch = nil
        busyObservationGeneration += 1
        status = .failed(Self.failure(for: failure))
        logger.info("Update cycle failed: domain=\(failure.domain, privacy: .public) code=\(failure.code)")
        return
      }
    }
    if case .staged = status { return }
    status = availableUpdateVersion.map { .available(version: $0) }
      ?? .idle(lastChecked: lastUpdateCheckDate)
  }

  nonisolated static func failure(for error: NSError) -> Failure {
    if error.domain == NSURLErrorDomain { return .network }
    if error.domain == "SUSparkleErrorDomain" {
      if [3001, 3002].contains(error.code) { return .invalidSignature }
      if (4000..<5000).contains(error.code) { return .cannotInstall }
      if error.code == 2001 { return .network }
    }
    return .other
  }

}
