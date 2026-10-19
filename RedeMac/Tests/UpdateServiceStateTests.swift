import Observation
import XCTest

#if SPARKLE_ENABLED
  import Sparkle
#endif

@testable import Rede

final class UpdateServiceStateTests: XCTestCase {
  func testSecurityAndTransportErrorsMapToTypedFailures() {
    XCTAssertEqual(UpdateService.failure(for: NSError(domain: NSURLErrorDomain, code: -1009)), .network)
    XCTAssertEqual(UpdateService.failure(for: NSError(domain: "SUSparkleErrorDomain", code: 3001)), .invalidSignature)
    XCTAssertEqual(UpdateService.failure(for: NSError(domain: "SUSparkleErrorDomain", code: 3002)), .invalidSignature)
    XCTAssertEqual(UpdateService.failure(for: NSError(domain: "SUSparkleErrorDomain", code: 4005)), .cannotInstall)
    XCTAssertEqual(UpdateService.failure(for: NSError(domain: "other", code: 1)), .other)
  }

  #if SPARKLE_ENABLED
    @MainActor
    func testSparkleInstallAndRelaunchDelegateSelectorsAreExported() {
      let service = UpdateService(preferences: StateUpdatePreferences())
      XCTAssertTrue(service.responds(to:
        #selector(SPUUpdaterDelegate.updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:))))
      XCTAssertTrue(service.responds(to:
        #selector(SPUUpdaterDelegate.updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:))))
      XCTAssertTrue(service.responds(to:
        #selector(SPUUpdaterDelegate.updater(_:willDownloadUpdate:with:))))
    }
  #endif

  @MainActor
  func testChecksPreserveStagedAndDownloadingStateAndRequireReadiness() {
    let preferences = StateUpdatePreferences()
    let service = UpdateService(preferences: preferences)
    var installations = 0
    service.stageInstallation(version: "2") { installations += 1 }
    service.checkNow()
    XCTAssertEqual(service.status, .staged(version: "2"))
    XCTAssertEqual(service.availableUpdateVersion, "2")
    XCTAssertTrue(service.installStagedUpdateNow())
    XCTAssertEqual(installations, 1)
    service.startedDownload()
    service.checkNow()
    XCTAssertEqual(service.status, .downloading(fraction: nil))
    XCTAssertEqual(service.availableUpdateVersion, "2")

    preferences.canCheckForUpdates = false
    let unavailable = UpdateService(preferences: preferences)
    unavailable.checkNow()
    XCTAssertEqual(unavailable.status, .idle(lastChecked: nil))
  }

  @MainActor
  func testStagedInstallHandlerCanRetryButRejectsSynchronousReentrancy() {
    let service = UpdateService(preferences: StateUpdatePreferences())
    var installations = 0
    service.stageInstallation(version: "2") {
      installations += 1
      XCTAssertFalse(service.installStagedUpdateNow())
    }
    XCTAssertTrue(service.installStagedUpdateNow())
    XCTAssertTrue(service.installStagedUpdateNow())
    XCTAssertEqual(installations, 2)
  }

  @MainActor
  func testNormalSparkleAndCocoaCancellationsPreserveResumableInstallation() {
    let errors = [1001, 4007, 4008].map { NSError(domain: "SUSparkleErrorDomain", code: $0) }
      + [NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)]
    for error in errors {
      let service = UpdateService(preferences: StateUpdatePreferences())
      var installations = 0
      service.stageInstallation(version: "2") { installations += 1 }
      service.finishedUpdateCycle(error: error)
      XCTAssertEqual(service.status, .staged(version: "2"), "Normal cancellation: \(error.code)")
      XCTAssertTrue(service.installStagedUpdateNow())
      XCTAssertEqual(installations, 1)
    }
  }

  @MainActor
  func testFailureClearsDeferredRelaunchAndBusyClosureReassignmentFlushesOnce() {
    let failed = UpdateService(preferences: StateUpdatePreferences())
    failed.isBusy = { true }
    XCTAssertTrue(failed.postponeRelaunchIfBusy(version: "2") { XCTFail("Failed update resumed") })
    failed.finishedUpdateCycle(error: URLError(.notConnectedToInternet))
    failed.isBusy = { false }
    XCTAssertEqual(failed.status, .failed(.network))

    let service = UpdateService(preferences: StateUpdatePreferences())
    var relaunches = 0
    service.isBusy = { true }
    XCTAssertTrue(service.postponeRelaunchIfBusy(version: "2") { relaunches += 1 })
    service.isBusy = { false }
    service.isBusy = { false }
    XCTAssertEqual(relaunches, 1)
  }

  @MainActor
  func testBusyIdleBusyBeforeObservationHopDoesNotResumeUntilActuallyIdle() async {
    let service = UpdateService(preferences: StateUpdatePreferences())
    let busy = ObservableUpdateBusyState()
    var relaunches = 0
    let resumed = expectation(description: "Resumed only after the final idle transition")
    service.isBusy = { busy.value }
    XCTAssertTrue(service.postponeRelaunchIfBusy(version: "2") {
      relaunches += 1
      resumed.fulfill()
    })
    busy.value = false
    busy.value = true
    await Task.yield()
    XCTAssertEqual(relaunches, 0)
    busy.value = false
    await fulfillment(of: [resumed], timeout: 2)
    XCTAssertEqual(relaunches, 1)
  }

  @MainActor
  func testObservedBusyToIdleResumesRequestedRelaunchOnce() async {
    let service = UpdateService(preferences: StateUpdatePreferences())
    let busy = ObservableUpdateBusyState()
    let resumed = expectation(description: "Requested relaunch resumed")
    var count = 0
    service.isBusy = { busy.value }
    XCTAssertTrue(service.postponeRelaunchIfBusy(version: "2") {
      count += 1
      resumed.fulfill()
    })
    busy.value = false
    await fulfillment(of: [resumed], timeout: 2)
    service.busyStateDidChange()
    XCTAssertEqual(count, 1)
  }

  @MainActor
  func testBusyGateRefusesImmediateInstallAndIdleDoesNotAutoInstallStagedUpdate() {
    let service = UpdateService(preferences: StateUpdatePreferences())
    var busy = true
    var installations = 0
    service.isBusy = { busy }
    service.stageInstallation(version: "2") { installations += 1 }

    XCTAssertFalse(service.installStagedUpdateNow())
    XCTAssertEqual(installations, 0)
    busy = false
    service.busyStateDidChange()
    XCTAssertEqual(installations, 0)
    XCTAssertTrue(service.installStagedUpdateNow())
    XCTAssertEqual(installations, 1)
    XCTAssertTrue(service.installStagedUpdateNow())
    XCTAssertEqual(installations, 2)
  }

  @MainActor
  func testAlreadyRequestedRelaunchFlushesExactlyOnceWhenBusyEnds() {
    let service = UpdateService(preferences: StateUpdatePreferences())
    var busy = true
    var relaunches = 0
    service.isBusy = { busy }
    XCTAssertTrue(service.postponeRelaunchIfBusy(version: "2") { relaunches += 1 })
    service.busyStateDidChange()
    XCTAssertEqual(relaunches, 0)

    busy = false
    service.busyStateDidChange()
    service.busyStateDidChange()
    XCTAssertEqual(relaunches, 1)
    XCTAssertFalse(service.postponeRelaunchIfBusy(version: "2") { relaunches += 1 })
    XCTAssertEqual(relaunches, 1)
  }

  @MainActor
  func testScheduledWindowsAreHiddenWhileBusyButManualChecksRemainAvailable() {
    let service = UpdateService(preferences: StateUpdatePreferences())
    service.isBusy = { true }
    XCTAssertFalse(service.shouldShowScheduledUpdate(immediateFocus: true))
    service.checkNow()
    XCTAssertEqual(service.status, .checking)
    service.isBusy = { false }
    XCTAssertTrue(service.shouldShowScheduledUpdate(immediateFocus: true))
    XCTAssertFalse(service.shouldShowScheduledUpdate(immediateFocus: false))
  }

  @MainActor
  func testStatusTransitionsKeepStagedStateAndDiscardInstallationAfterFailure() {
    let service = UpdateService(preferences: StateUpdatePreferences())
    service.foundUpdate(version: "2")
    XCTAssertEqual(service.status, .available(version: "2"))
    service.startedDownload()
    XCTAssertEqual(service.status, .downloading(fraction: nil))
    service.stageInstallation(version: "2") { XCTFail("Failed updates must not install") }
    service.finishedUpdateCycle(error: nil)
    XCTAssertEqual(service.status, .staged(version: "2"))

    service.finishedUpdateCycle(error: URLError(.notConnectedToInternet))
    XCTAssertEqual(service.status, .failed(.network))
    XCTAssertFalse(service.installStagedUpdateNow())
  }
}

@Observable
private final class ObservableUpdateBusyState {
  var value = true
}

@MainActor
private final class StateUpdatePreferences: UpdatePreferences {
  var automaticallyChecksForUpdates = true
  var automaticallyDownloadsUpdates = true
  var sendsSystemProfile = false
  let lastUpdateCheckDate: Date? = nil
  var canCheckForUpdates = true
}
