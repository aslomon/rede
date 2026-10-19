import Foundation

/// Why a network-backed switch is shown disabled. The view maps each case to German copy.
enum NetworkFeatureBlock: Equatable {
  /// Secure-local is on: nothing is sent to OpenAI. The stored switch stays as is, but is inert.
  case secureLocal
  case localRewrite
  case noAPIKey
  case noMicrophone
}

/// Live-transcript switch. Pure over the current settings.
struct LiveSettingsModel {
  let settings: AppSettings
  let hasAPIKey: Bool
  let microphoneAuthorized: Bool

  /// Live always streams the microphone to OpenAI, so it follows the online transcription path.
  var availability: LiveAvailability {
    LiveAvailability.resolve(
      featureEnabled: settings.liveTranscriptionEnabled,
      secureLocal: settings.secureLocalModeEnabled, backendIsRemote: true,
      hasAPIKey: hasAPIKey, microphoneAuthorized: microphoneAuthorized)
  }

  var isOn: Bool { settings.liveTranscriptionEnabled }

  /// The switch is shown but cannot be changed while secure-local is on.
  var canToggle: Bool { !settings.secureLocalModeEnabled }

  /// True only when live would really run: opted in AND available.
  var isEffective: Bool { availability == .available }

  var block: NetworkFeatureBlock? {
    if settings.secureLocalModeEnabled { return .secureLocal }
    guard isOn else { return nil }
    if case .unavailable(let reason) = availability {
      switch reason {
      case .noAPIKey: return .noAPIKey
      case .noMicrophone: return .noMicrophone
      case .localBackend: return .localRewrite
      case .secureLocal: return .secureLocal
      case .featureOff: return nil
      }
    }
    return nil
  }

  func setting(_ enabled: Bool) -> AppSettings {
    var updated = settings
    updated.liveTranscriptionEnabled = enabled
    return updated
  }
}

/// Automatik (purpose routing) switches: one global switch plus one switch per mode.
/// Every edit touches only its own field: Automatik can never turn on field context, memory or
/// e-mail memory for a mode.
struct PurposeRoutingSettingsModel {
  let settings: AppSettings
  let hasAPIKey: Bool

  var isEnabled: Bool { settings.purposeRoutingEnabled }
  var includesFieldText: Bool { settings.purposeRoutingIncludesFieldText }
  var canToggle: Bool { !settings.secureLocalModeEnabled }

  var block: NetworkFeatureBlock? {
    if settings.secureLocalModeEnabled { return .secureLocal }
    return hasAPIKey ? nil : .noAPIKey
  }

  /// Only modes with a rewrite step offer Automatik (E-Mail, Prompt, Social, custom rewrites);
  /// plain dictation has nothing to format.
  func offersMode(_ config: ModeConfig) -> Bool { config.kind.rewritesText }

  func modeToggleEnabled(_ config: ModeConfig, rewriteBackend: RewriteBackend) -> Bool {
    offersMode(config) && isEnabled && canToggle && rewriteBackend == .openai
  }

  func settingEnabled(_ enabled: Bool) -> AppSettings {
    var updated = settings
    updated.purposeRoutingEnabled = enabled
    return updated
  }

  func settingFieldText(_ included: Bool) -> AppSettings {
    var updated = settings
    updated.purposeRoutingIncludesFieldText = included
    return updated
  }

  func settingMode(_ mode: PurposeRoutingMode, on config: ModeConfig) -> ModeConfig {
    var updated = config
    updated.rewrite.purposeRouting = mode
    return updated
  }
}
