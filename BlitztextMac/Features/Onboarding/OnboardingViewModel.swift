import Observation
import SwiftUI

/// Drives the first-run wizard. Owns the step cursor, the per-step advance gating, and the
/// editable example-prompt drafts that get persisted into the E-Mail and Prompt modes on advance.
/// All persistence routes through `AppState` so the wizard never touches `settings.json` directly.
@Observable
@MainActor
final class OnboardingViewModel {
  enum OnboardingStep: Int, CaseIterable, Identifiable {
    /// Brand intro + the user's name (writing perspective) — one decision, asked once.
    case welcome
    case installLocation
    case permissions
    case processing
    case models
    case modes
    /// Hold-vs-toggle decision plus a read-only keycap overview of the default mode hotkeys.
    case hotkeys
    /// Small opt-in comfort toggles: launch at login, sound feedback, local archive & memory.
    case extras
    case finish

    var id: Int { rawValue }

    /// 1-based position for the "schritt n von N" indicator.
    var displayIndex: Int { rawValue + 1 }

    var title: String {
      switch self {
      case .welcome: return "start"
      case .installLocation: return "speicherort"
      case .permissions: return "rechte"
      case .processing: return "verarbeitung"
      case .models: return "modelle"
      case .modes: return "modi"
      case .hotkeys: return "hotkeys"
      case .extras: return "extras"
      case .finish: return "fertig"
      }
    }

    var systemImage: String {
      switch self {
      case .welcome: return "sparkles"
      case .installLocation: return "arrow.down.app"
      case .permissions: return "hand.raised.fill"
      case .processing: return "cpu"
      case .models: return "shippingbox"
      case .modes: return "text.badge.checkmark"
      case .hotkeys: return "keyboard"
      case .extras: return "slider.horizontal.3"
      case .finish: return "checkmark.circle.fill"
      }
    }

    var accent: Color {
      switch self {
      case .welcome, .processing: return .blue
      case .installLocation, .permissions: return .orange
      case .models, .finish: return .green
      case .modes: return .purple
      case .hotkeys: return .indigo
      case .extras: return .cyan
      }
    }

    var primaryActionLabel: String {
      switch self {
      case .processing: return "auswahl prüfen"
      case .models: return "modelle prüfen"
      case .finish: return "fertig"
      default: return "weiter"
      }
    }

    /// Centered hero headline shown by the wizard chrome — the step views render only their
    /// controls. rede voice: short, lowercase, may show character.
    var headline: String {
      switch self {
      case .welcome: return "lass uns reden."
      case .installLocation: return "der richtige ort."
      case .permissions: return "zwei freigaben."
      case .processing: return "wo soll's laufen?"
      case .models: return "deine lokalen engines."
      case .modes: return "deine modi."
      case .hotkeys: return "von überall."
      case .extras: return "noch ein feinschliff?"
      case .finish: return "sitzt."
      }
    }

    /// One-line supporting sentence under the headline (centered, secondary).
    var subheadline: String {
      switch self {
      case .welcome:
        return "einmal einrichten — danach: sprechen, loslassen, text sitzt im feld."
      case .installLocation:
        return "eine kopie in /Applications hält start, updates und hotkeys stabil."
      case .permissions:
        return "mikrofon nimmt auf, bedienungshilfen fügen direkt ein."
      case .processing:
        return "online-leistung oder alles lokal — du entscheidest."
      case .models:
        return "Whisper für sprache → text, optional ein modell fürs umformen."
      case .modes:
        return "E-Mail, Prompt und Social sind vorbereitet — pass die beispiele an."
      case .hotkeys:
        return "ein hotkey pro modus — halten oder umschalten."
      case .extras:
        return "alles optional, alles später änderbar."
      case .finish:
        return "dein setup im überblick — mit \u{201E}fertig\u{201C} legst du los."
      }
    }
  }

  static let stepCount = OnboardingStep.allCases.count

  var step: OnboardingStep = .welcome

  /// Editable drafts for the two curated example prompts, seeded from the live mode config so a
  /// returning user sees their own prompt, and a fresh user sees the `ModeDefaults` example.
  var emailPrompt: String
  var promptPrompt: String
  private let isOpenAIKeyConfigured: () -> Bool

  init(
    appState: AppState,
    isOpenAIKeyConfigured: @escaping () -> Bool = { KeychainService.isConfigured }
  ) {
    self.isOpenAIKeyConfigured = isOpenAIKeyConfigured
    emailPrompt = Self.seededPrompt(for: .textImprover, appState: appState)
    promptPrompt = Self.seededPrompt(for: .dampfAblassen, appState: appState)
  }

  private static func seededPrompt(for type: WorkflowType, appState: AppState) -> String {
    let current = appState.modeConfig(for: type).rewrite.systemPrompt
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !current.isEmpty { return current }
    return ModeConfig.defaultRewrite(for: type).systemPrompt
  }

  // MARK: - Navigation

  func back() {
    guard let index = OnboardingStep.allCases.firstIndex(of: step), index > 0 else { return }
    step = OnboardingStep.allCases[index - 1]
  }

  func next() {
    guard let index = OnboardingStep.allCases.firstIndex(of: step),
      index < OnboardingStep.allCases.count - 1
    else { return }
    step = OnboardingStep.allCases[index + 1]
  }

  var isFirstStep: Bool { step == .welcome }
  var isLastStep: Bool { step == .finish }

  /// Soft gating: only the steps that would otherwise leave the app unusable block the primary
  /// button. Permissions are intentionally soft-warned (always advanceable). The welcome step asks
  /// for the name (writing perspective) and blocks until it is non-empty.
  func canAdvance(_ appState: AppState) -> Bool {
    switch step {
    case .installLocation, .permissions, .modes, .hotkeys, .extras, .finish:
      return true
    case .welcome:
      return !appState.appSettings.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
    case .processing:
      return appState.appSettings.secureLocalModeEnabled || isOpenAIKeyConfigured()
    case .models:
      return appState.appSettings.secureLocalModeEnabled
        ? appState.selectedLocalModelIsInstalled
        : true
    }
  }

  // MARK: - Persistence

  /// Writes the two example-prompt drafts back into their modes. Called on every advance off the
  /// modes step and on finish so the user's edits are never lost.
  func persistPrompts(_ appState: AppState) {
    let email = emailPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = promptPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    appState.updateMode(.textImprover) { $0.rewrite.systemPrompt = email }
    appState.updateMode(.dampfAblassen) { $0.rewrite.systemPrompt = prompt }
  }

  /// Resets a draft back to the curated `ModeDefaults` example (the "beispiel" link).
  func restoreExample(for type: WorkflowType) {
    let example = ModeConfig.defaultRewrite(for: type).systemPrompt
    switch type {
    case .textImprover: emailPrompt = example
    case .dampfAblassen: promptPrompt = example
    default: break
    }
  }

  /// Wizard completion: persist drafts, flip the launch-gating flag, and mark onboarding seen.
  func finish(_ appState: AppState) {
    persistPrompts(appState)
    appState.appSettings.hasCompletedOnboarding = true
    appState.markOnboardingSeen()
  }
}
