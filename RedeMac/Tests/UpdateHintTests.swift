import XCTest

@testable import Rede

/// The popover footer cue and the settings install button must route to the right service call
/// for every status. `.staged` used to expose a hint whose click (a check) was a deliberate no-op.
@MainActor
final class UpdateHintTests: XCTestCase {
  private func model(
    _ fake: FakeUpdates, busy: Bool = false, available: Bool = true
  ) -> UpdateSettingsModel {
    UpdateSettingsModel(service: fake, updatesAvailable: available, isBusy: { busy })
  }

  func testStagedCueInstallsInsteadOfChecking() throws {
    let fake = FakeUpdates()
    fake.status = .staged(version: "1.2")
    fake.availableUpdateVersion = "1.2"
    let updates = model(fake)

    let hint = try XCTUnwrap(updates.footerHint)
    XCTAssertEqual(hint.action, .install)
    XCTAssertTrue(hint.isEnabled)
    XCTAssertEqual(hint.label, "update auf 1.2 installieren")

    XCTAssertTrue(updates.performFooterHint())
    XCTAssertEqual(fake.installCalls, 1)
    XCTAssertEqual(fake.checkNowCalls, 0, "a check is a no-op while staged")
  }

  func testStagedCueWaitsDuringDictationAndNeverInterruptsIt() throws {
    let fake = FakeUpdates()
    fake.status = .staged(version: "1.2")
    fake.availableUpdateVersion = "1.2"
    let updates = model(fake, busy: true)

    let hint = try XCTUnwrap(updates.footerHint)
    XCTAssertFalse(hint.isEnabled)
    XCTAssertEqual(hint.help, "geht erst, wenn dein diktat fertig ist.")
    XCTAssertFalse(updates.performFooterHint())
    XCTAssertEqual(fake.installCalls, 0)
  }

  func testRefusedInstallIsReportedAndNeverClaimsARestart() {
    let fake = FakeUpdates()
    fake.status = .staged(version: "1.2")
    fake.availableUpdateVersion = "1.2"
    fake.installResult = false  // postponed relaunch: no staged handler to invoke
    let updates = model(fake)

    XCTAssertFalse(updates.installNow())
    XCTAssertTrue(updates.installNotStarted)
    let detail = updates.statusLine.detail(
      waitsForDictation: false, installNotStarted: updates.installNotStarted)
    XCTAssertEqual(detail, "starten ging gerade nicht. das update bleibt bereit.")
    XCTAssertFalse(detail?.contains("neu") ?? true, "no restart promise when nothing started")
    XCTAssertTrue(updates.offersInstall, "the button stays so the user can try again")
  }

  func testSuccessfulInstallOrNewCheckClearsTheRefusal() {
    let fake = FakeUpdates()
    fake.status = .staged(version: "1.2")
    fake.installResult = false
    let updates = model(fake)
    updates.installNow()
    XCTAssertTrue(updates.installNotStarted)

    fake.installResult = true
    XCTAssertTrue(updates.installNow())
    XCTAssertFalse(updates.installNotStarted)

    fake.installResult = false
    updates.installNow()
    updates.checkNow()
    XCTAssertFalse(updates.installNotStarted)
  }

  func testSettingsKeepsTheInstallButtonForAPostponedRelaunchWithoutVersion() {
    let fake = FakeUpdates()
    fake.status = .staged(version: "1.2")
    fake.availableUpdateVersion = nil  // postponed relaunch: no gentle reminder was recorded
    let updates = model(fake)

    XCTAssertTrue(updates.offersInstall)
    XCTAssertTrue(updates.canInstallNow)
    XCTAssertNil(updates.footerHint, "the footer cue needs a version to name")
  }

  func testAvailableCueChecksAndNeverInstalls() throws {
    let fake = FakeUpdates()
    fake.status = .available(version: "1.2")
    fake.availableUpdateVersion = "1.2"
    let updates = model(fake)

    let hint = try XCTUnwrap(updates.footerHint)
    XCTAssertEqual(hint.action, .check)
    XCTAssertEqual(hint.label, "update auf 1.2 verfügbar")
    XCTAssertFalse(updates.offersInstall)

    XCTAssertTrue(updates.performFooterHint())
    XCTAssertEqual(fake.checkNowCalls, 1)
    XCTAssertEqual(fake.installCalls, 0)
  }

  func testCueIsDisabledWhileCheckingOrDownloadingInsteadOfDoingNothing() throws {
    let fake = FakeUpdates()
    fake.availableUpdateVersion = "1.2"
    for status in [UpdateService.Status.checking, .downloading(fraction: 0.4)] {
      fake.status = status
      let updates = model(fake)
      XCTAssertFalse(try XCTUnwrap(updates.footerHint).isEnabled)
      XCTAssertFalse(updates.performFooterHint())
    }
    XCTAssertEqual(fake.checkNowCalls, 0)
    XCTAssertEqual(fake.installCalls, 0)
  }

  func testNoCueWithoutAnUpdateOrOnABuildWithoutTheUpdater() {
    let fake = FakeUpdates()
    fake.status = .idle(lastChecked: nil)
    XCTAssertNil(model(fake).footerHint)

    fake.status = .staged(version: "1.2")
    fake.availableUpdateVersion = "1.2"
    XCTAssertNil(model(fake, available: false).footerHint)
    XCTAssertFalse(model(fake, available: false).offersInstall)
  }
}
