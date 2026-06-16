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

    XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86_400, "daily check interval")
    XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
    XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
    // Privacy: Sparkle system profiling must never be enabled.
    XCTAssertNil(info["SUEnableSystemProfiling"], "system profiling must stay absent")
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
