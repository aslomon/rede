import Observation
import XCTest

@testable import Rede

#if SPARKLE_ENABLED
  import Sparkle

  final class UpdateServicePrivacyTests: XCTestCase {
    func testHostedApplicationSupportUsesConfiguredIsolatedHome() throws {
      let environment = ProcessInfo.processInfo.environment
      guard let expectedHome = environment["REDE_EXPECTED_TEST_HOME"] else {
        throw XCTSkip("Requires an explicitly isolated app-hosted test invocation")
      }
      XCTAssertEqual(environment["CFFIXED_USER_HOME"], expectedHome)
      func canonical(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
      }
      let expected = canonical(expectedHome)
      let actualHome = canonical(NSHomeDirectory())
      let support = try XCTUnwrap(FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask).first)
        .resolvingSymlinksInPath().standardizedFileURL
      let expectedSupport = expected.appendingPathComponent("Library/Application Support", isDirectory: true)
      let redeSupport = AppSupportPaths.appSupportDirectoryURL
        .resolvingSymlinksInPath().standardizedFileURL
      XCTAssertEqual(actualHome, expected)
      XCTAssertEqual(support, expectedSupport)
      XCTAssertEqual(redeSupport, expectedSupport.appendingPathComponent("rede", isDirectory: true))
      let proof = ["expectedHome": expected.path, "actualHome": actualHome.path,
                   "foundationAppSupport": support.path, "redeAppSupport": redeSupport.path]
      let data = try JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys])
      print("REDE_HOST_ISOLATION_PROOF " + (try XCTUnwrap(String(data: data, encoding: .utf8))))
    }

    @MainActor
    func testDefaultInitializerDoesNotStartUpdaterOrPersistPreferencesUnderXCTest() throws {
      _ = try XCTUnwrap(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"],
                        "App-hosted tests must provide the XCTest startup marker")
      XCTAssertNotNil(NSClassFromString("XCTestCase"))
      let identifier = try XCTUnwrap(Bundle.main.bundleIdentifier)
      let defaults = UserDefaults.standard
      let before = defaults.persistentDomain(forName: identifier) ?? [:]

      let service = UpdateService()
      service.setAutomaticChecksEnabled(true)
      service.setAutomaticDownloadsEnabled(true)
      service.checkForUpdates()
      service.refresh()

      XCTAssertFalse(service.canCheckForUpdates)
      XCTAssertFalse(service.automaticChecksEnabled)
      XCTAssertFalse(service.automaticDownloadsEnabled)
      XCTAssertNil(service.lastUpdateCheckDate)
      XCTAssertTrue(NSDictionary(dictionary: before).isEqual(
        to: defaults.persistentDomain(forName: identifier) ?? [:]),
        "Hosted updater must not change real preferences")
    }

    @MainActor
    func testRealSparkleIgnoresDownloadPreferenceWritesWhileChecksAreDisabled() throws {
      for stored in [false, true] {
        let fixture = try isolatedUpdater(downloads: stored)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.identifier) }
        let service = UpdateService(preferences: fixture.updater)
        service.setAutomaticChecksEnabled(false)
        service.setAutomaticDownloadsEnabled(!stored)
        XCTAssertFalse(service.automaticDownloadsEnabled)
        XCTAssertEqual(fixture.defaults.bool(forKey: "SUAutomaticallyUpdate"), stored)
        service.setAutomaticChecksEnabled(true)
        XCTAssertEqual(service.automaticDownloadsEnabled, stored)
      }
    }

    @MainActor
    func testSparkleDelegatesStageDownloadAndDeferRelaunchWhileBusy() throws {
      let fixture = try isolatedUpdater()
      defer { fixture.defaults.removePersistentDomain(forName: fixture.identifier) }
      let service = UpdateService(preferences: fixture.updater)
      let item = try XCTUnwrap(SUAppcastItem(dictionary: [
        "enclosure": ["url": "https://example.invalid/rede.zip", "sparkle:version": "2",
                      "sparkle:shortVersionString": "2", "length": "1"]]))
      let request = NSMutableURLRequest(url: try XCTUnwrap(URL(string: "https://example.invalid/rede.zip")))
      service.updater(fixture.updater, willDownloadUpdate: item, with: request)
      XCTAssertEqual(service.status, .downloading(fraction: nil))
      var installations = 0
      XCTAssertTrue(service.updater(fixture.updater, willInstallUpdateOnQuit: item) { installations += 1 })
      XCTAssertEqual(service.status, .staged(version: "2"))
      service.isBusy = { true }
      XCTAssertFalse(service.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: true))
      XCTAssertFalse(service.installStagedUpdateNow())
      XCTAssertTrue(service.updater(fixture.updater, shouldPostponeRelaunchForUpdate: item) { installations += 1 })
      service.isBusy = { false }
      XCTAssertEqual(installations, 1)
      XCTAssertTrue(service.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: true))
    }

    @MainActor
    func testStoredDownloadOptOutSurvivesEnabledPlistDefault() throws {
      let fixture = try isolatedUpdater(downloads: false)
      defer { fixture.defaults.removePersistentDomain(forName: fixture.identifier) }
      XCTAssertTrue(fixture.updater.automaticallyChecksForUpdates)
      XCTAssertFalse(fixture.updater.automaticallyDownloadsUpdates)

      let service = UpdateService(preferences: fixture.updater)

      XCTAssertTrue(service.automaticChecksEnabled)
      XCTAssertFalse(service.automaticDownloadsEnabled)
      XCTAssertFalse(fixture.defaults.bool(forKey: "SUAutomaticallyUpdate"))
    }

    @MainActor
    func testExistingProfileConsentIsDisabledBeforeStartupAndDelegateAlwaysDeniesKeys() throws {
      let fixture = try isolatedUpdater()
      defer { fixture.defaults.removePersistentDomain(forName: fixture.identifier) }
      XCTAssertTrue(fixture.updater.sendsSystemProfile)
      var startupCount = 0

      let service = UpdateService(preferences: fixture.updater, startUpdater: {
        XCTAssertFalse(fixture.updater.sendsSystemProfile)
        startupCount += 1
      })

      XCTAssertEqual(startupCount, 1)
      XCTAssertFalse(fixture.updater.sendsSystemProfile)
      XCTAssertFalse(fixture.defaults.bool(forKey: "SUSendProfileInfo"))
      XCTAssertTrue(fixture.defaults.bool(forKey: "SUEnableAutomaticChecks"))
      XCTAssertTrue(fixture.defaults.bool(forKey: "SUAutomaticallyUpdate"))
      fixture.updater.sendsSystemProfile = true
      XCTAssertEqual(service.allowedSystemProfileKeys(for: fixture.updater), [])
      XCTAssertTrue(service.responds(to: #selector(SPUUpdaterDelegate.allowedSystemProfileKeys(for:))))
    }

    @MainActor
    func testExternalSparkleChangesRefreshEffectiveDownloadStateThroughKVO() async throws {
      let fixture = try isolatedUpdater()
      defer { fixture.defaults.removePersistentDomain(forName: fixture.identifier) }
      let service = UpdateService(preferences: fixture.updater)
      XCTAssertTrue(service.automaticChecksEnabled)
      XCTAssertTrue(service.automaticDownloadsEnabled)

      let disabled = expectation(description: "Effective automatic downloads disabled")
      withObservationTracking {
        _ = service.automaticDownloadsEnabled
      } onChange: { disabled.fulfill() }
      fixture.updater.automaticallyChecksForUpdates = false
      await fulfillment(of: [disabled], timeout: 2)
      XCTAssertFalse(service.automaticChecksEnabled)
      XCTAssertFalse(service.automaticDownloadsEnabled)
      XCTAssertTrue(fixture.defaults.bool(forKey: "SUAutomaticallyUpdate"))

      let restored = expectation(description: "Stored automatic downloads restored")
      withObservationTracking {
        _ = service.automaticDownloadsEnabled
      } onChange: { restored.fulfill() }
      fixture.updater.automaticallyChecksForUpdates = true
      await fulfillment(of: [restored], timeout: 2)
      XCTAssertTrue(service.automaticChecksEnabled)
      XCTAssertTrue(service.automaticDownloadsEnabled)
    }

    private struct Fixture {
      let updater: SPUUpdater
      let defaults: UserDefaults
      let identifier: String
    }

    @MainActor
    private func isolatedUpdater(downloads: Bool = true) throws -> Fixture {
      let identifier = "app.rede.updater-tests.\(UUID().uuidString)"
      let bundleURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(identifier).app", isDirectory: true)
      let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
      let info: [String: Any] = [
        "CFBundleIdentifier": identifier, "CFBundleName": "rede updater test",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "SUEnableAutomaticChecks": true, "SUAutomaticallyUpdate": true
      ]
      let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      try data.write(to: contents.appendingPathComponent("Info.plist"))
      let bundle = try XCTUnwrap(Bundle(url: bundleURL))
      let defaults = try XCTUnwrap(UserDefaults(suiteName: identifier))
      defaults.set(true, forKey: "SUSendProfileInfo")
      defaults.set(true, forKey: "SUEnableAutomaticChecks")
      defaults.set(downloads, forKey: "SUAutomaticallyUpdate")
      let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
      let updater = SPUUpdater(
        hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
      return Fixture(updater: updater, defaults: defaults, identifier: identifier)
    }
  }
#endif
