import XCTest

@testable import Blitztext

/// Locks down the wizard's gating, prompt-draft seeding, and completion side effects. The view
/// model is the headless core of the onboarding flow, so testing it covers the wizard's behaviour
/// without driving SwiftUI. Keychain-dependent branches use injected stubs so the suite never
/// blocks on macOS security prompts.
@MainActor
final class OnboardingViewModelTests: XCTestCase {

  private func makeAppState() -> AppState {
    let state = AppState()
    // Start every case from a known, non-completed, online baseline.
    state.appSettings.hasCompletedOnboarding = false
    state.appSettings.secureLocalModeEnabled = false
    return state
  }

  // MARK: - Step shape

  func testJourneyStepsInExpectedOrder() {
    XCTAssertEqual(OnboardingViewModel.stepCount, 10)
    XCTAssertEqual(
      OnboardingViewModel.OnboardingStep.allCases,
      [
        .welcome, .installLocation, .permissions, .processing, .models, .modes, .hotkeys,
        .dictationTest, .extras, .finish,
      ])
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.welcome.displayIndex, 1)
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.finish.displayIndex, 10)
  }

  func testJourneyStepsExposeShortMetadata() {
    // rede voice: rail titles are lowercase.
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.installLocation.title, "speicherort")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.hotkeys.title, "hotkeys")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.dictationTest.title, "test")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.extras.title, "extras")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.permissions.systemImage, "hand.raised.fill")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.hotkeys.systemImage, "keyboard")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.dictationTest.systemImage, "mic.circle.fill")
    XCTAssertEqual(
      OnboardingViewModel.OnboardingStep.processing.primaryActionLabel, "auswahl prüfen")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.finish.primaryActionLabel, "fertig")
  }

  /// Every step must provide the wizard-hero copy (headline + subheadline) — the step views no
  /// longer carry their own headers, so missing metadata would render an empty hero.
  func testEveryStepProvidesHeroCopy() {
    for step in OnboardingViewModel.OnboardingStep.allCases {
      XCTAssertFalse(step.headline.isEmpty, "\(step) needs a headline")
      XCTAssertFalse(step.subheadline.isEmpty, "\(step) needs a subheadline")
      XCTAssertFalse(step.systemImage.isEmpty, "\(step) needs a hero symbol")
    }
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.welcome.headline, "lass uns reden.")
    XCTAssertEqual(OnboardingViewModel.OnboardingStep.finish.headline, "sitzt.")
  }

  // MARK: - canAdvance gating

  func testSoftStepsAlwaysAdvanceable() {
    let appState = makeAppState()
    let vm = OnboardingViewModel(appState: appState)

    for step in [
      OnboardingViewModel.OnboardingStep.installLocation, .permissions, .modes, .hotkeys,
      .dictationTest, .extras, .finish,
    ] {
      vm.step = step
      XCTAssertTrue(vm.canAdvance(appState), "\(step) must always advance (soft gating)")
    }
  }

  func testWelcomeNeedsName() {
    let appState = makeAppState()
    let vm = OnboardingViewModel(appState: appState)
    vm.step = .welcome

    appState.appSettings.userDisplayName = "   "
    XCTAssertFalse(vm.canAdvance(appState))

    appState.appSettings.userDisplayName = "Jason Rinnert"
    XCTAssertTrue(vm.canAdvance(appState))
  }

  func testProcessingOnlineNeedsKey() {
    let appState = makeAppState()
    appState.appSettings.secureLocalModeEnabled = false
    let vm = OnboardingViewModel(appState: appState, isOpenAIKeyConfigured: { false })
    vm.step = .processing

    XCTAssertFalse(vm.canAdvance(appState))

    let configuredVM = OnboardingViewModel(appState: appState, isOpenAIKeyConfigured: { true })
    configuredVM.step = .processing
    XCTAssertTrue(configuredVM.canAdvance(appState))
  }

  func testProcessingLocalAdvancesWithoutKey() {
    let appState = makeAppState()
    appState.appSettings.secureLocalModeEnabled = true
    let vm = OnboardingViewModel(appState: appState)
    vm.step = .processing

    // Secure local mode never needs an OpenAI key.
    XCTAssertTrue(vm.canAdvance(appState))
  }

  func testModelsOnlineWithKeyAdvancesWithoutLocalWhisper() {
    let appState = makeAppState()
    appState.appSettings.secureLocalModeEnabled = false
    let vm = OnboardingViewModel(appState: appState, isOpenAIKeyConfigured: { true })
    vm.step = .models

    // Online with OpenAI: local Whisper is optional.
    XCTAssertTrue(vm.canAdvance(appState))
  }

  func testModelsWithoutKeyNeedsInstalledWhisper() {
    let appState = makeAppState()
    appState.appSettings.secureLocalModeEnabled = false
    let vm = OnboardingViewModel(appState: appState, isOpenAIKeyConfigured: { false })
    vm.step = .models

    XCTAssertEqual(vm.canAdvance(appState), appState.selectedLocalModelIsInstalled)
  }

  func testModelsLocalNeedsInstalledModel() {
    let appState = makeAppState()
    appState.appSettings.secureLocalModeEnabled = true
    let vm = OnboardingViewModel(appState: appState)
    vm.step = .models

    // Local: advance is gated on an actually-installed model.
    XCTAssertEqual(vm.canAdvance(appState), appState.selectedLocalModelIsInstalled)
  }

  // MARK: - Navigation

  func testNextAndBackTraverseSteps() {
    let appState = makeAppState()
    let vm = OnboardingViewModel(appState: appState)

    XCTAssertTrue(vm.isFirstStep)
    vm.next()
    XCTAssertEqual(vm.step, .installLocation)
    vm.next()
    XCTAssertEqual(vm.step, .permissions)
    vm.next()
    XCTAssertEqual(vm.step, .processing)
    vm.back()
    XCTAssertEqual(vm.step, .permissions)
    vm.back()
    XCTAssertEqual(vm.step, .installLocation)
    vm.back()
    XCTAssertEqual(vm.step, .welcome)
    // Back at the first step is a no-op.
    vm.back()
    XCTAssertEqual(vm.step, .welcome)

    vm.step = .modes
    vm.next()
    XCTAssertEqual(vm.step, .hotkeys)
    vm.next()
    XCTAssertEqual(vm.step, .dictationTest)
    vm.next()
    XCTAssertEqual(vm.step, .extras)
    vm.next()
    XCTAssertEqual(vm.step, .finish)
    XCTAssertTrue(vm.isLastStep)
    // Next at the last step is a no-op.
    vm.next()
    XCTAssertEqual(vm.step, .finish)
  }

  // MARK: - Prompt-draft seeding

  func testPromptDraftsSeededFromModeDefaultsForFreshState() {
    let appState = makeAppState()
    // Clear any persisted prompts so the fresh-user fallback to ModeDefaults is exercised.
    appState.updateMode(.textImprover) { $0.rewrite.systemPrompt = "" }
    appState.updateMode(.dampfAblassen) { $0.rewrite.systemPrompt = "" }

    let vm = OnboardingViewModel(appState: appState)
    XCTAssertEqual(vm.emailPrompt, ModeDefaults.emailSystemPrompt)
    XCTAssertEqual(vm.promptPrompt, ModeDefaults.promptCraftSystemPrompt)
  }

  func testPromptDraftsSeededFromExistingUserPrompt() {
    let appState = makeAppState()
    appState.updateMode(.textImprover) { $0.rewrite.systemPrompt = "Mein eigener Prompt" }

    let vm = OnboardingViewModel(appState: appState)
    XCTAssertEqual(vm.emailPrompt, "Mein eigener Prompt")
  }

  func testRestoreExampleResetsDraftToDefault() {
    let appState = makeAppState()
    let vm = OnboardingViewModel(appState: appState)
    vm.emailPrompt = "geändert"
    vm.restoreExample(for: .textImprover)
    XCTAssertEqual(vm.emailPrompt, ModeDefaults.emailSystemPrompt)
  }

  // MARK: - Persistence

  func testPersistPromptsWritesDraftsIntoModes() {
    let appState = makeAppState()
    let vm = OnboardingViewModel(appState: appState)
    vm.emailPrompt = "  E-Mail Prompt  "
    vm.promptPrompt = "Prompt Prompt"
    vm.socialPrompt = "Social Prompt"
    vm.persistPrompts(appState)

    XCTAssertEqual(
      appState.modeConfig(for: .textImprover).rewrite.systemPrompt, "E-Mail Prompt")
    XCTAssertEqual(
      appState.modeConfig(for: .dampfAblassen).rewrite.systemPrompt, "Prompt Prompt")
    XCTAssertEqual(
      appState.modeConfig(for: .emojiText).rewrite.systemPrompt, "Social Prompt")
  }

  // MARK: - finish()

  func testFinishFlipsHasCompletedOnboardingAndMarksSeen() {
    let appState = makeAppState()
    XCTAssertFalse(appState.appSettings.hasCompletedOnboarding)

    let vm = OnboardingViewModel(appState: appState)
    vm.emailPrompt = "Final E-Mail"
    vm.finish(appState)

    XCTAssertTrue(appState.appSettings.hasCompletedOnboarding)
    XCTAssertTrue(appState.appSettings.hasSeenOnboarding)
    // finish also persists the current drafts.
    XCTAssertEqual(appState.modeConfig(for: .textImprover).rewrite.systemPrompt, "Final E-Mail")
  }
}
