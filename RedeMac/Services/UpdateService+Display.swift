import Foundation

extension UpdateService {
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
      calendar.isDate(date, inSameDayAs: yesterday) {
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
