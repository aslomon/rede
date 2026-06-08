import Foundation

enum AppSupportPaths {
  private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.blitztext.mac"

  static var appSupportDirectoryURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
      .appendingPathComponent("Blitztext", isDirectory: true)
  }

  static var settingsURL: URL {
    appSupportDirectoryURL.appendingPathComponent("settings.json")
  }

  static var localModelsDirectoryURL: URL {
    appSupportDirectoryURL.appendingPathComponent("models", isDirectory: true)
  }

  /// Text-only transcription archive (Phase 4a). Directory is created lazily, files are 0600.
  static var archiveDirectoryURL: URL {
    appSupportDirectoryURL.appendingPathComponent("archive", isDirectory: true)
  }

  static var archiveURL: URL {
    archiveDirectoryURL.appendingPathComponent("history.json")
  }

  /// Two-speed Memory store (Phase 4b). Separate from settings.json, 0600, opt-in.
  static var memoryURL: URL {
    appSupportDirectoryURL.appendingPathComponent("memory.json")
  }

  /// On-device "Office Memory" context log (MEM-1). Metadata only — no dictated text. 0600, opt-in.
  static var contextLogURL: URL {
    archiveDirectoryURL.appendingPathComponent("context-log.json")
  }

  /// On-device "Verbesserungs-Erkennung" log (MEM-2). Records before → after of the user's manual
  /// corrections to learn from them. 0600, opt-in (requires archive + improvement detection on).
  static var improvementLogURL: URL {
    archiveDirectoryURL.appendingPathComponent("improvement-log.json")
  }

  static var whisperKitModelsDirectoryURL: URL {
    localModelsDirectoryURL.appendingPathComponent("whisperkit", isDirectory: true)
  }

  static var llamaCppModelsDirectoryURL: URL {
    localModelsDirectoryURL.appendingPathComponent("llamacpp", isDirectory: true)
  }

  static var defaultWhisperKitModelURL: URL {
    whisperKitModelsDirectoryURL.appendingPathComponent(
      "openai_whisper-large-v3-v20240930_626MB",
      isDirectory: true
    )
  }

  static var cachesDirectoryURL: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      .first!
      .appendingPathComponent(bundleIdentifier, isDirectory: true)
  }

  static var preferencesURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier).plist")
  }

  static var savedApplicationStateDirectoryURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Saved Application State", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true)
  }

  static func ensureAppSupportDirectoryExists() throws {
    try FileManager.default.createDirectory(
      at: appSupportDirectoryURL,
      withIntermediateDirectories: true
    )
  }
}
