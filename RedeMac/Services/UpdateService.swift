import Foundation
import Observation
import os

#if SPARKLE_ENABLED
  import Sparkle
#endif

/// Wraps the Sparkle updater behind a small app-facing service (pattern: `LaunchAtLoginService`).
/// All Sparkle types stay behind `SPARKLE_ENABLED` so a Mac App Store build can compile the
/// framework out entirely (stores forbid self-updating apps) without touching any call sites.
///
/// Privacy: the scheduled daily check requests only the appcast feed over HTTPS (standard HTTP
/// metadata, app version in the user agent). Sparkle's system profiling stays disabled — no
/// hardware/usage data ever leaves the Mac. See docs/privacy.md.
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

  private let logger = Logger(subsystem: "app.rede.mac", category: "Updates")

  #if SPARKLE_ENABLED
    private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
  #endif

  override init() {
    super.init()
    #if SPARKLE_ENABLED
      let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: self
      )
      updaterController = controller
      // canCheckForUpdates flips while a session runs; Sparkle documents it as KVO-observable.
      canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial]) {
        [weak self] updater, _ in
        let newValue = updater.canCheckForUpdates
        Task { @MainActor [weak self] in
          self?.canCheckForUpdates = newValue
        }
      }
      refresh()
    #endif
  }

  /// User-initiated check — shows Sparkle's standard UI (progress, release notes, install).
  func checkForUpdates() {
    #if SPARKLE_ENABLED
      availableUpdateVersion = nil
      updaterController?.checkForUpdates(nil)
    #endif
  }

  func setAutomaticChecksEnabled(_ enabled: Bool) {
    #if SPARKLE_ENABLED
      updaterController?.updater.automaticallyChecksForUpdates = enabled
      refresh()
    #endif
  }

  func refresh() {
    #if SPARKLE_ENABLED
      guard let updater = updaterController?.updater else { return }
      automaticChecksEnabled = updater.automaticallyChecksForUpdates
      lastUpdateCheckDate = updater.lastUpdateCheckDate
    #endif
  }

  // MARK: - Display helpers (pure, unit-tested)

  var appVersionText: String {
    Self.versionDisplayText(
      shortVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    )
  }

  var lastCheckDisplayText: String {
    Self.lastCheckDisplayText(for: lastUpdateCheckDate)
  }

  nonisolated static func versionDisplayText(shortVersion: String?, build: String?) -> String {
    let version: String
    if let shortVersion, !shortVersion.isEmpty {
      version = shortVersion
    } else {
      version = "?"
    }
    if let build, !build.isEmpty, build != version {
      return "version \(version) (build \(build))"
    }
    return "version \(version)"
  }

  nonisolated static func lastCheckDisplayText(
    for date: Date?,
    now: Date = Date(),
    calendar: Calendar = Calendar.current
  ) -> String {
    guard let date else { return "noch nie nach updates gesucht." }
    if calendar.isDate(date, inSameDayAs: now) { return "zuletzt geprüft: heute." }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday)
    {
      return "zuletzt geprüft: gestern."
    }
    let days =
      calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: date),
        to: calendar.startOfDay(for: now)
      ).day ?? 0
    // A future timestamp (clock skew) must never render as "vor -N tagen".
    guard days > 0 else { return "zuletzt geprüft: heute." }
    return "zuletzt geprüft: vor \(days) tagen."
  }

  /// Quiet popover hint label for a pending gentle reminder; nil when no update waits.
  nonisolated static func updateHintText(forVersion version: String?) -> String? {
    guard let version, !version.isEmpty else { return nil }
    return "update auf \(version) verfügbar"
  }
}

#if SPARKLE_ENABLED
  // MARK: - SPUUpdaterDelegate

  extension UpdateService: SPUUpdaterDelegate {
    nonisolated func updater(
      _ updater: SPUUpdater,
      didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
      error: Error?
    ) {
      Task { @MainActor [weak self] in
        self?.refresh()
        if let error {
          // "No update found" and user cancellation are normal cycle ends, not failures.
          self?.logger.info(
            "Update cycle finished: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  // MARK: - SPUStandardUserDriverDelegate (gentle reminders)

  /// rede is an `LSUIElement` menu bar app: scheduled update alerts must not steal focus
  /// while the user dictates. Sparkle's gentle-reminders flow lets us surface a quiet hint in the
  /// popover instead; the standard Sparkle UI only appears for user-initiated checks (or once the
  /// user clicks the hint).
  extension UpdateService: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
      _ update: SUAppcastItem,
      andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
      // Only let Sparkle pop its window when the app already has focus (practically never for a
      // menu bar app); otherwise we take over and show the quiet popover hint.
      immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
      _ handleShowingUpdate: Bool,
      forUpdate update: SUAppcastItem,
      state: SPUUserUpdateState
    ) {
      guard !state.userInitiated else { return }
      let version = update.displayVersionString
      Task { @MainActor [weak self] in
        self?.availableUpdateVersion = version
      }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
      Task { @MainActor [weak self] in
        self?.availableUpdateVersion = nil
      }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
      Task { @MainActor [weak self] in
        self?.availableUpdateVersion = nil
      }
    }
  }
#endif
