import Foundation
import Observation

/// The slice of `UpdateService` the settings UI needs. A seam for tests; `UpdateService` conforms.
@MainActor
protocol UpdateControlling: AnyObject {
  var status: UpdateService.Status { get }
  var availableUpdateVersion: String? { get }
  var automaticChecksEnabled: Bool { get }
  var automaticDownloadsEnabled: Bool { get }
  var canCheckForUpdates: Bool { get }
  func setAutomaticChecksEnabled(_ enabled: Bool)
  func setAutomaticDownloadsEnabled(_ enabled: Bool)
  func checkNow()
  @discardableResult func installStagedUpdateNow() -> Bool
}

extension UpdateService: UpdateControlling {}

/// What the status line says. No copy here: the view maps each case to German text.
enum UpdateStatusLine: Equatable {
  case unavailable
  case idle(lastChecked: Date?)
  case checking
  case downloading(fraction: Double?)
  case available(version: String)
  case staged(version: String)
  case failed(UpdateService.Failure)

  init(status: UpdateService.Status, updatesAvailable: Bool) {
    guard updatesAvailable else {
      self = .unavailable
      return
    }
    switch status {
    case .idle(let lastChecked): self = .idle(lastChecked: lastChecked)
    case .checking: self = .checking
    case .downloading(let fraction): self = .downloading(fraction: fraction)
    case .available(let version): self = .available(version: version)
    case .staged(let version): self = .staged(version: version)
    case .failed(let failure): self = .failed(failure)
    }
  }
}

/// What the popover footer offers while an update waits. The model decides the action and whether
/// it can run right now; the view only renders it.
struct UpdateHint: Equatable {
  enum Action: Equatable {
    /// `.available`: opens the standard update UI via a manual check.
    case check
    /// `.staged`: a check is a deliberate no-op there, so the cue installs instead.
    case install
  }

  let label: String
  let action: Action
  let isEnabled: Bool
  let help: String
}

/// Settings logic for updates. Mirrors the service's stored-versus-effective semantics instead of
/// copying them into `AppSettings`: with checks off, the effective download value is `false` and
/// the download control is disabled; turning checks back on restores the stored choice.
@MainActor
@Observable
final class UpdateSettingsModel {
  private let service: any UpdateControlling
  private let isBusy: @MainActor () -> Bool
  private let updatesAvailable: Bool
  /// The last install request was refused by the service (nothing staged to start, or a dictation
  /// began in the meantime). Shown calmly; never turned into a restart claim.
  private(set) var installNotStarted = false

  init(
    service: any UpdateControlling, updatesAvailable: Bool = UpdateService.isAvailable,
    isBusy: @escaping @MainActor () -> Bool
  ) {
    self.service = service
    self.updatesAvailable = updatesAvailable
    self.isBusy = isBusy
  }

  var statusLine: UpdateStatusLine {
    UpdateStatusLine(status: service.status, updatesAvailable: updatesAvailable)
  }

  var automaticChecks: Bool {
    get { service.automaticChecksEnabled }
    set { service.setAutomaticChecksEnabled(newValue) }
  }

  /// The EFFECTIVE value: false whenever checks are off, even if the stored choice is true.
  var automaticDownloads: Bool {
    get { service.automaticDownloadsEnabled }
    set { service.setAutomaticDownloadsEnabled(newValue) }
  }

  var canChangeDownloads: Bool { updatesAvailable && service.automaticChecksEnabled }

  var canCheckNow: Bool {
    guard updatesAvailable, service.canCheckForUpdates else { return false }
    if case .checking = service.status { return false }
    return true
  }

  /// The install button exists whenever the service reports `.staged`. That includes an
  /// already-requested postponed relaunch, which carries no `availableUpdateVersion`.
  var offersInstall: Bool {
    guard updatesAvailable, case .staged = service.status else { return false }
    return true
  }

  /// A staged update exists and nothing is being recorded or processed right now.
  var canInstallNow: Bool {
    guard updatesAvailable, case .staged = service.status else { return false }
    return !isBusy()
  }

  /// A staged update is waiting only because a dictation is in progress.
  var installWaitsForDictation: Bool {
    guard updatesAvailable, case .staged = service.status else { return false }
    return isBusy()
  }

  /// Manual checks are never gated by a running dictation.
  func checkNow() {
    guard canCheckNow else { return }
    installNotStarted = false
    service.checkNow()
  }

  /// True only when the service actually started the installation. A `false` return (a postponed
  /// relaunch has no staged handler, or a dictation began) is recorded, not hidden.
  @discardableResult
  func installNow() -> Bool {
    guard canInstallNow else { return false }
    let started = service.installStagedUpdateNow()
    installNotStarted = !started
    return started
  }

  var installHelp: String {
    installWaitsForDictation
      ? "geht erst, wenn dein diktat fertig ist." : "rede startet danach neu."
  }

  /// The popover footer cue; nil when no update waits. While a check or download runs it stays
  /// visible but disabled, so a click can never silently do nothing.
  var footerHint: UpdateHint? {
    guard updatesAvailable, let version = service.availableUpdateVersion,
      let label = UpdateService.updateHintText(forVersion: version)
    else { return nil }
    switch service.status {
    case .staged:
      return UpdateHint(
        label: "update auf \(version) installieren", action: .install, isEnabled: canInstallNow,
        help: installHelp)
    case .checking, .downloading:
      return UpdateHint(label: label, action: .check, isEnabled: false, help: "lädt gerade …")
    default:
      return UpdateHint(
        label: label, action: .check, isEnabled: canCheckNow, help: "zeigt das update an.")
    }
  }

  /// Runs the footer cue's action. Returns whether anything was started.
  @discardableResult
  func performFooterHint() -> Bool {
    guard let hint = footerHint, hint.isEnabled else { return false }
    switch hint.action {
    case .check:
      checkNow()
      return true
    case .install:
      return installNow()
    }
  }
}
