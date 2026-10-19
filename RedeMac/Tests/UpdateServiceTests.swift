import XCTest

@testable import Rede

/// Pure display helpers of `UpdateService` plus the Info.plist contract the Sparkle updater
/// depends on (feed URL, daily interval, strict verification, a real EdDSA public key).
final class UpdateServiceTests: XCTestCase {

  // MARK: - versionDisplayText

  func testVersionDisplayTextShowsVersionAndBuild() {
    XCTAssertEqual(
      UpdateService.versionDisplayText(shortVersion: "1.6", build: "16"),
      "version 1.6 (build 16)"
    )
  }

  func testVersionDisplayTextOmitsBuildWhenMissingOrEqual() {
    XCTAssertEqual(UpdateService.versionDisplayText(shortVersion: "1.6", build: nil), "version 1.6")
    XCTAssertEqual(UpdateService.versionDisplayText(shortVersion: "1.6", build: ""), "version 1.6")
    XCTAssertEqual(
      UpdateService.versionDisplayText(shortVersion: "1.6", build: "1.6"), "version 1.6")
  }

  func testVersionDisplayTextFallsBackWhenVersionMissing() {
    XCTAssertEqual(UpdateService.versionDisplayText(shortVersion: nil, build: nil), "version ?")
    XCTAssertEqual(
      UpdateService.versionDisplayText(shortVersion: "", build: "7"), "version ? (build 7)")
  }

  // MARK: - lastCheckDisplayText

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    return utcCalendar.date(from: components)!
  }

  func testLastCheckDisplayTextNeverChecked() {
    XCTAssertEqual(
      UpdateService.lastCheckDisplayText(for: nil),
      "noch nie nach updates gesucht."
    )
  }

  func testLastCheckDisplayTextToday() {
    let now = utcDate(2026, 6, 10)
    let checked = utcDate(2026, 6, 10, hour: 3)
    XCTAssertEqual(
      UpdateService.lastCheckDisplayText(for: checked, now: now, calendar: utcCalendar),
      "zuletzt geprüft: heute."
    )
  }

  func testLastCheckDisplayTextYesterday() {
    let now = utcDate(2026, 6, 10)
    let checked = utcDate(2026, 6, 9, hour: 23)
    XCTAssertEqual(
      UpdateService.lastCheckDisplayText(for: checked, now: now, calendar: utcCalendar),
      "zuletzt geprüft: gestern."
    )
  }

  func testLastCheckDisplayTextDaysAgo() {
    let now = utcDate(2026, 6, 10)
    let checked = utcDate(2026, 6, 5)
    XCTAssertEqual(
      UpdateService.lastCheckDisplayText(for: checked, now: now, calendar: utcCalendar),
      "zuletzt geprüft: vor 5 tagen."
    )
  }

  /// A future timestamp (clock skew) must never render as "vor -N tagen".
  func testLastCheckDisplayTextFutureDateClampsToToday() {
    let now = utcDate(2026, 6, 10)
    let checked = utcDate(2026, 6, 12)
    XCTAssertEqual(
      UpdateService.lastCheckDisplayText(for: checked, now: now, calendar: utcCalendar),
      "zuletzt geprüft: heute."
    )
  }

  // MARK: - updateHintText

  func testUpdateHintTextNilForMissingVersion() {
    XCTAssertNil(UpdateService.updateHintText(forVersion: nil))
    XCTAssertNil(UpdateService.updateHintText(forVersion: ""))
  }

  func testUpdateHintTextNamesVersion() {
    XCTAssertEqual(
      UpdateService.updateHintText(forVersion: "2.0"),
      "update auf 2.0 verfügbar"
    )
  }

  // MARK: - Info.plist contract (tests run hosted inside the app bundle)

  func testBundleDeclaresSparkleFeedConfiguration() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)

    let feed = try XCTUnwrap(info["SUFeedURL"] as? String, "SUFeedURL missing")
    let feedURL = try XCTUnwrap(URL(string: feed), "SUFeedURL is not a valid URL")
    XCTAssertEqual(feedURL.scheme, "https", "appcast must be served over HTTPS")
    XCTAssertEqual(feedURL.absoluteString,
      "https://github.com/aslomon/rede/releases/latest/download/appcast.xml")

    XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86_400, "daily check interval")
    XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
    XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, true)
    XCTAssertEqual(info["SUSendProfileInfo"] as? Bool, false)
    XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
    // The profiling prompt stays hidden; runtime policy separately blocks outgoing profile data.
    XCTAssertNil(info["SUEnableSystemProfiling"], "system profiling prompt must stay absent")
  }

  /// The public key must be a REAL Ed25519 key (32 bytes base64) — the build-time placeholder
  /// must never ship. Generated via Sparkle's `generate_keys`; see docs/release-process.md.
  func testBundleDeclaresRealEdDSAPublicKey() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)
    let key = try XCTUnwrap(info["SUPublicEDKey"] as? String, "SUPublicEDKey missing")
    let decoded = Data(base64Encoded: key)
    XCTAssertEqual(decoded?.count, 32, "SUPublicEDKey must be a base64 Ed25519 public key")
  }
}

final class UpdateServicePreferencesTests: XCTestCase {
  func testSystemProfileIsDisabledBeforeStartupWithoutChangingUpdateChoices() async {
    await MainActor.run {
      for checks in [false, true] {
        for downloads in [false, true] {
          let preferences = TestUpdatePreferences(checks: checks, downloads: downloads)
          var startupCount = 0
          _ = UpdateService(preferences: preferences, startUpdater: {
            XCTAssertFalse(preferences.sendsSystemProfile)
            startupCount += 1
          })

          XCTAssertEqual(startupCount, 1)
          XCTAssertFalse(preferences.sendsSystemProfile)
          XCTAssertEqual(preferences.automaticallyChecksForUpdates, checks)
          XCTAssertEqual(preferences.storedDownloads, downloads)
          XCTAssertEqual(preferences.writeCount, 0)
        }
      }
    }
  }

  func testExistingPreferencesArePreservedWhenServiceStarts() async {
    await MainActor.run {
      let preferences = TestUpdatePreferences(checks: false, downloads: false)
      let service = UpdateService(preferences: preferences)

      XCTAssertFalse(service.automaticChecksEnabled)
      XCTAssertFalse(service.automaticDownloadsEnabled)
      XCTAssertEqual(preferences.writeCount, 0)
    }
  }

  func testDownloadPreferenceChangesWithoutChangingChecks() async {
    await MainActor.run {
      let preferences = TestUpdatePreferences(checks: true, downloads: false)
      let service = UpdateService(preferences: preferences)

      service.setAutomaticDownloadsEnabled(true)
      XCTAssertTrue(preferences.automaticallyDownloadsUpdates)
      XCTAssertTrue(service.automaticDownloadsEnabled)
      XCTAssertTrue(service.automaticChecksEnabled)

      service.setAutomaticDownloadsEnabled(false)
      XCTAssertFalse(preferences.automaticallyDownloadsUpdates)
      XCTAssertFalse(service.automaticDownloadsEnabled)
    }
  }

  func testCheckPreferencePreservesStoredDownloadsAndRestoresThemWhenReenabled() async {
    await MainActor.run {
      let preferences = TestUpdatePreferences(checks: true, downloads: true)
      let service = UpdateService(preferences: preferences)

      service.setAutomaticChecksEnabled(false)
      XCTAssertFalse(preferences.automaticallyChecksForUpdates)
      XCTAssertFalse(service.automaticChecksEnabled)
      XCTAssertFalse(service.automaticDownloadsEnabled)
      XCTAssertTrue(preferences.storedDownloads)

      service.setAutomaticChecksEnabled(true)
      XCTAssertTrue(service.automaticDownloadsEnabled)
    }
  }

  func testRefreshMirrorsExternallyChangedPreferencesAndStatus() async {
    await MainActor.run {
      let preferences = TestUpdatePreferences(checks: true, downloads: false)
      let service = UpdateService(preferences: preferences)
      let checkedAt = Date(timeIntervalSince1970: 1234)
      preferences.automaticallyDownloadsUpdates = true
      preferences.automaticallyChecksForUpdates = false
      preferences.lastUpdateCheckDate = checkedAt
      preferences.canCheckForUpdates = true

      service.refresh()

      XCTAssertFalse(service.automaticChecksEnabled)
      XCTAssertFalse(service.automaticDownloadsEnabled)
      XCTAssertTrue(preferences.storedDownloads)
      XCTAssertEqual(service.lastUpdateCheckDate, checkedAt)
      XCTAssertTrue(service.canCheckForUpdates)

      preferences.automaticallyChecksForUpdates = true
      service.refresh()
      XCTAssertTrue(service.automaticDownloadsEnabled)
    }
  }

}

@MainActor
private final class TestUpdatePreferences: UpdatePreferences {
  var writeCount = 0
  var automaticallyChecksForUpdates: Bool { didSet { writeCount += 1 } }
  private(set) var storedDownloads: Bool
  var automaticallyDownloadsUpdates: Bool {
    get { automaticallyChecksForUpdates && storedDownloads }
    set {
      guard automaticallyChecksForUpdates else { return }
      storedDownloads = newValue
      writeCount += 1
    }
  }
  var sendsSystemProfile = true
  var lastUpdateCheckDate: Date?
  var canCheckForUpdates = false

  init(checks: Bool, downloads: Bool) {
    automaticallyChecksForUpdates = checks
    storedDownloads = downloads
  }
}
