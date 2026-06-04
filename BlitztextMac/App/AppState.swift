import AppKit
import Observation
import SwiftUI

enum PopoverPage: Equatable {
  case main
  case onboarding
  case settings
  case workflow
}

@Observable
@MainActor
final class AppState {
  private static let pasteRetryInitialAttempts = 22
  private static let concealedPasteboardType = NSPasteboard.PasteboardType(
    "org.nspasteboard.ConcealedType")

  var activeWorkflow: (any Workflow)?
  var page: PopoverPage = .main
  var isPopoverShown = false
  var menuBarStatus: MenuBarStatus = .idle {
    didSet {
      guard oldValue != menuBarStatus else { return }
      onMenuBarStatusChange?(menuBarStatus)
    }
  }
  var accessibilityPermissionGranted = false
  var localModelDownloadProgress: Double?
  var localModelDownloadStatusText: String?
  var localModelDownloadErrorText: String?
  var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
  private var activeLaunchSource: WorkflowLaunchSource = .manual
  private var activePasteTarget: PasteTarget?
  private var lastPopoverPasteTarget: PasteTarget?
  private var menuBarStatusResetTask: Task<Void, Never>?
  private var workflowCleanupTask: Task<Void, Never>?

  // Persisted settings
  var appSettings: AppSettings {
    didSet {
      saveSettings()
      prewarmLocalTranscriptionIfNeeded()
    }
  }
  var transcriptionSettings: TranscriptionSettings {
    didSet { saveSettings() }
  }
  var textImprovementSettings: TextImprovementSettings {
    didSet { saveSettings() }
  }
  var dampfAblassenSettings: DampfAblassenSettings {
    didSet { saveSettings() }
  }
  var emojiTextSettings: EmojiTextSettings {
    didSet { saveSettings() }
  }

  // Phase 4: text-only archive + two-speed Memory (opt-in, default OFF).
  let archiveStore = ArchiveStore()
  let memoryStore = MemoryStore()
  let memoryCoordinator: MemoryCoordinator

  // Hotkeys
  let hotkeyService = HotkeyService()

  // Computed
  var isConfigured: Bool {
    KeychainService.isConfigured || !LocalTranscriptionService.installedModels().isEmpty
  }
  var shouldShowOnboarding: Bool {
    !isConfigured && !appSettings.hasSeenOnboarding
  }

  var currentPhase: WorkflowPhase {
    activeWorkflow?.phase ?? .idle
  }

  init() {
    self.appSettings = Self.loadAppSettings()
    self.transcriptionSettings = Self.loadTranscriptionSettings()
    self.textImprovementSettings = Self.loadTextImprovementSettings()
    self.dampfAblassenSettings = Self.loadDampfAblassenSettings()
    self.emojiTextSettings = Self.loadEmojiTextSettings()
    self.memoryCoordinator = MemoryCoordinator(
      memory: memoryStore, archive: archiveStore)
    migrateToModeConfigsIfNeeded()
    refreshAccessibilityPermission()
    autoSelectFastLocalModelIfNeeded()
    prewarmLocalTranscriptionIfNeeded()
    runMemoryLaunchMaintenanceIfNeeded()
    startAccessibilityMonitoring()
    observeAppActivation()
  }

  /// Re-checks Accessibility whenever the app becomes active (e.g. the user comes back from
  /// System Settings after toggling the permission).
  private func observeAppActivation() {
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refreshAccessibilityPermission()
      }
    }
  }

  // MARK: - Memory maintenance (Phase 4)

  /// App-launch catch-up (hash-gated, skips when the archive is unchanged) plus the daily
  /// decay/prune pass. Only runs while Memory is enabled; otherwise it is a no-op.
  private func runMemoryLaunchMaintenanceIfNeeded() {
    guard appSettings.memoryContextEnabled else { return }
    memoryCoordinator.runDailyPassIfNeeded()
    Task { await memoryCoordinator.catchUpIfNeeded() }
  }

  /// User-facing "Jetzt analysieren": full recompute of the candidate index over the archive.
  /// The injected (confirmed) set is preserved — only suggestions change.
  func recomputeMemory() {
    Task { await memoryCoordinator.recomputeMemory() }
  }

  /// Confirmed-memory terms + the user's customTerms, ranked and capped, for the Whisper hint.
  /// The user's own terms come first; ranked memory terms follow (best last in the joined hint).
  var effectiveCustomTerms: [String] {
    var seen = Set<String>()
    var result: [String] = []
    func add(_ term: String) {
      let trimmed = term.trimmingCharacters(in: .whitespaces)
      let key = trimmed.lowercased()
      guard !trimmed.isEmpty, !seen.contains(key) else { return }
      seen.insert(key)
      result.append(trimmed)
    }
    // Build the list MOST-IMPORTANT-FIRST so the cap keeps the highest-priority terms:
    // explicit user terms first, then memory terms best-first (rankedInjectionTerms is best-LAST → reverse).
    for term in textImprovementSettings.customTerms { add(term) }
    guard appSettings.memoryContextEnabled else {
      return Array(result.prefix(MemoryStore.injectionCap))
    }
    for term in memoryStore.rankedInjectionTerms().reversed() { add(term) }
    // Cap to the top-priority terms, then reverse so the best terms sit LAST in the Whisper hint
    // (whisper-1 drops the earliest tokens when the prompt overflows its budget).
    return Array(result.prefix(MemoryStore.injectionCap)).reversed()
  }

  /// The structured Memory block for the rewrite prompt — non-nil only when the GLOBAL master
  /// and the per-mode toggle are both on. Gating lives here so plain Diktat stays untouched.
  func memoryContext(for type: WorkflowType) -> MemoryContext? {
    guard appSettings.memoryContextEnabled else { return nil }
    guard modeConfig(for: type).rewrite.useMemoryContext else { return nil }
    let context = memoryStore.context
    return context.isEmpty ? nil : context
  }

  // MARK: - Memory curation (changes the injected set)

  /// Suggestions surfaced in the archive UI (scored, recurring, not yet confirmed/denied).
  var memorySuggestions: [MemoryCandidate] { memoryStore.suggestions }
  var memoryConfirmedTerms: [MemoryConfirmedTerm] { memoryStore.confirmed }
  var isRecomputingMemory: Bool { memoryCoordinator.isRecomputing }

  func confirmMemory(_ candidate: MemoryCandidate) { memoryStore.confirm(candidate) }
  func confirmMemory(term: String, category: MemoryCategory) {
    memoryStore.confirm(term: term, category: category)
  }
  func denyMemory(_ candidate: MemoryCandidate) { memoryStore.deny(candidate) }
  func unconfirmMemory(_ id: MemoryConfirmedTerm.ID) { memoryStore.unconfirm(id) }

  // MARK: - Archive / Memory toggles + deletion (privacy)

  var isArchiveEnabled: Bool {
    get { appSettings.archiveEnabled }
    set { appSettings.archiveEnabled = newValue }
  }

  var isMemoryContextEnabled: Bool {
    get { appSettings.memoryContextEnabled }
    set {
      appSettings.memoryContextEnabled = newValue
      if newValue { runMemoryLaunchMaintenanceIfNeeded() }
    }
  }

  func clearArchive() { archiveStore.clear() }
  func clearMemory() { memoryStore.clear() }

  // MARK: - Model picker state

  var availableModelIDs: [String] = []
  var isLoadingModels = false
  var modelLoadError: String?

  func loadAvailableModels() {
    guard !isLoadingModels else { return }
    isLoadingModels = true
    modelLoadError = nil
    Task {
      do {
        let ids = try await RewriteModelRegistry.fetchAvailableChatModels()
        availableModelIDs = ids
        isLoadingModels = false
      } catch {
        modelLoadError = error.localizedDescription
        isLoadingModels = false
      }
    }
  }

  // MARK: - Mode configs

  func modeConfig(for type: WorkflowType) -> ModeConfig {
    appSettings.modes[type.rawValue] ?? .default(for: type)
  }

  func updateMode(_ type: WorkflowType, _ transform: (inout ModeConfig) -> Void) {
    var config = modeConfig(for: type)
    transform(&config)
    appSettings.modes[type.rawValue] = config
  }

  func resetMode(_ type: WorkflowType) {
    appSettings.modes[type.rawValue] = .default(for: type)
  }

  /// Effective rewrite backend: the global offline switch forces on-device.
  func resolvedRewriteBackend(for type: WorkflowType) -> RewriteBackend {
    appSettings.secureLocalModeEnabled
      ? .local : modeConfig(for: type).rewrite.rewriteBackend
  }

  /// Transcription backend for the rewrite modes — local in secure offline mode so audio never
  /// leaves the device, otherwise OpenAI Whisper. Mirrors the plain transcription mode.
  var rewriteTranscriptionBackend: TranscriptionBackend {
    appSettings.secureLocalModeEnabled ? .local : .remote
  }

  func rewriteProvider(for type: WorkflowType) -> any RewriteProvider {
    switch resolvedRewriteBackend(for: type) {
    case .local:
      // Local rewriting runs through Ollama (a local HTTP server). If Ollama is down or the
      // model is missing, the provider throws a guiding error at runtime instead of failing here.
      return OllamaRewriteProvider(modelID: appSettings.selectedLocalLLMModelName)
    case .openai:
      return OpenAIRewriteProvider(modelID: modeConfig(for: type).rewrite.modelID)
    }
  }

  func rewriteBackendReady(for type: WorkflowType) -> Bool {
    switch resolvedRewriteBackend(for: type) {
    case .local:
      // Configured by definition — Ollama needs no API key. A down server surfaces as a clear
      // runtime error that guides the user to install/start Ollama and pull a model.
      return true
    case .openai:
      return KeychainService.isConfigured
    }
  }

  private func migrateToModeConfigsIfNeeded() {
    guard !appSettings.didMigrateToModeConfigs else { return }

    var modes = appSettings.modes

    func ensure(_ slot: WorkflowType, _ build: () -> ModeConfig) {
      if modes[slot.rawValue] == nil { modes[slot.rawValue] = build() }
    }

    ensure(.transcription) { .default(for: .transcription) }
    ensure(.localTranscription) { .default(for: .localTranscription) }

    ensure(.textImprover) {
      var cfg = ModeConfig.default(for: .textImprover)
      if !textImprovementSettings.customName.isEmpty {
        cfg.userName = textImprovementSettings.customName
      }
      if !textImprovementSettings.systemPrompt.isEmpty {
        cfg.rewrite.systemPrompt = textImprovementSettings.systemPrompt
      }
      cfg.rewrite.tone = textImprovementSettings.tone
      cfg.rewrite.context = textImprovementSettings.context
      return cfg
    }

    ensure(.dampfAblassen) {
      var cfg = ModeConfig.default(for: .dampfAblassen)
      if !dampfAblassenSettings.customName.isEmpty {
        cfg.userName = dampfAblassenSettings.customName
      }
      // Only keep a user-customized prompt; the stock "calm down" default is replaced by the curated Prompt default.
      let stock = DampfAblassenSettings().systemPrompt
      if !dampfAblassenSettings.systemPrompt.isEmpty, dampfAblassenSettings.systemPrompt != stock {
        cfg.rewrite.systemPrompt = dampfAblassenSettings.systemPrompt
      }
      return cfg
    }

    ensure(.emojiText) {
      var cfg = ModeConfig.default(for: .emojiText)
      if !emojiTextSettings.customName.isEmpty { cfg.userName = emojiTextSettings.customName }
      cfg.rewrite.emojiDensity = emojiTextSettings.emojiDensity
      return cfg
    }

    appSettings.modes = modes
    appSettings.didMigrateToModeConfigs = true
    // Preserve the user's offline choice: a previously-enabled "secure local mode" now simply routes
    // both transcription AND rewriting on-device (local model) instead of disabling rewrite.
    // We never silently flip it — fresh installs default to false via the AppSettings property default.
    // didSet does NOT fire during init mutations — persist explicitly.
    saveSettings()
  }

  // MARK: - Custom Display Names

  func displayName(for type: WorkflowType) -> String {
    let name = modeConfig(for: type).userName.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? ModeConfig.defaultUserName(for: type) : name
  }

  func workflowSubtitle(for type: WorkflowType) -> String {
    switch type {
    case .transcription:
      if appSettings.secureLocalModeEnabled {
        let modelName = selectedLocalModelName
        return LocalTranscriptionService.isModelInstalled(modelName)
          ? "Lokal: \(LocalTranscriptionModel.displayName(for: modelName))."
          : "Lokales WhisperKit-Modell fehlt."
      }
      return "Online: Whisper über OpenAI."
    case .localTranscription:
      return "Nur lokal. Kein Server."
    case .textImprover, .dampfAblassen, .emojiText:
      switch resolvedRewriteBackend(for: type) {
      case .local:
        let model = appSettings.selectedLocalLLMModelName.trimmingCharacters(
          in: .whitespacesAndNewlines)
        return model.isEmpty
          ? "Lokal über Ollama — noch kein Modell gewählt"
          : "Lokal über Ollama (\(model))"
      case .openai:
        return type.subtitle
      }
    }
  }

  var resolvedLocalModelName: String {
    LocalTranscriptionService.resolvedModelName(appSettings.selectedLocalTranscriptionModelName)
  }

  var selectedLocalModelDisplayName: String {
    LocalTranscriptionModel.displayName(for: selectedLocalModelName)
  }

  var selectedLocalModelName: String {
    LocalTranscriptionService.normalizedModelName(appSettings.selectedLocalTranscriptionModelName)
  }

  var selectedLocalModelIsInstalled: Bool {
    LocalTranscriptionService.isModelInstalled(selectedLocalModelName)
  }

  var isDownloadingLocalModel: Bool {
    localModelDownloadProgress != nil
  }

  var localModelDownloadButtonTitle: String {
    selectedLocalModelIsInstalled
      ? "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) ist installiert"
      : "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) installieren"
  }

  // MARK: - Workflow Management

  func startWorkflow(_ type: WorkflowType, source: WorkflowLaunchSource = .manual) {
    guard isWorkflowAvailable(type) else {
      if source == .manual {
        page = .settings
      }
      return
    }

    activeWorkflow?.stop()
    menuBarStatusResetTask?.cancel()
    workflowCleanupTask?.cancel()
    activeLaunchSource = source
    activePasteTarget = capturePasteTarget(for: source)
    let selection = captureSelectionContext(for: type)

    switch type {
    case .transcription:
      let workflow = TranscriptionWorkflow(
        customTerms: effectiveCustomTerms,
        language: transcriptionSettings.language,
        backend: appSettings.secureLocalModeEnabled ? .local : .remote,
        localModelName: selectedLocalModelName
      )
      configureWorkflowHandlers(workflow)
      activeWorkflow = workflow
      workflow.start()

    case .localTranscription:
      let workflow = TranscriptionWorkflow(
        type: .localTranscription,
        customTerms: effectiveCustomTerms,
        language: transcriptionSettings.language,
        backend: .local,
        localModelName: selectedLocalModelName
      )
      configureWorkflowHandlers(workflow)
      activeWorkflow = workflow
      workflow.start()

    case .textImprover:
      let workflow = TextImprovementWorkflow(
        rewrite: modeConfig(for: .textImprover).rewrite,
        provider: rewriteProvider(for: .textImprover),
        customTerms: effectiveCustomTerms,
        language: transcriptionSettings.language,
        backend: rewriteTranscriptionBackend,
        localModelName: selectedLocalModelName,
        selection: selection,
        memoryContext: memoryContext(for: .textImprover)
      )
      configureWorkflowHandlers(workflow)
      activeWorkflow = workflow
      workflow.start()

    case .dampfAblassen:
      let workflow = DampfAblassenWorkflow(
        rewrite: modeConfig(for: .dampfAblassen).rewrite,
        provider: rewriteProvider(for: .dampfAblassen),
        customTerms: effectiveCustomTerms,
        language: transcriptionSettings.language,
        backend: rewriteTranscriptionBackend,
        localModelName: selectedLocalModelName,
        selection: selection,
        memoryContext: memoryContext(for: .dampfAblassen)
      )
      configureWorkflowHandlers(workflow)
      activeWorkflow = workflow
      workflow.start()

    case .emojiText:
      let workflow = EmojiTextWorkflow(
        rewrite: modeConfig(for: .emojiText).rewrite,
        provider: rewriteProvider(for: .emojiText),
        customTerms: effectiveCustomTerms,
        language: transcriptionSettings.language,
        backend: rewriteTranscriptionBackend,
        localModelName: selectedLocalModelName
      )
      configureWorkflowHandlers(workflow)
      activeWorkflow = workflow
      workflow.start()
    }

    page = source.presentsWorkflowPage ? .workflow : .main
  }

  func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
    guard modeConfig(for: type).isEnabled else { return false }
    switch type {
    case .localTranscription:
      return selectedLocalModelIsInstalled
    case .transcription:
      return appSettings.secureLocalModeEnabled
        ? selectedLocalModelIsInstalled
        : KeychainService.isConfigured
    case .textImprover, .dampfAblassen, .emojiText:
      let transcriptionReady =
        appSettings.secureLocalModeEnabled
        ? selectedLocalModelIsInstalled
        : KeychainService.isConfigured
      return transcriptionReady && rewriteBackendReady(for: type)
    }
  }

  /// Captures the user's text selection for reply/edit modes, only when that mode opts in.
  private func captureSelectionContext(for type: WorkflowType) -> SelectionContext? {
    // Only the E-Mail mode exposes the reply-context control today.
    guard type == .textImprover else { return nil }
    guard modeConfig(for: type).rewrite.replyContextMode != .off else { return nil }
    return SelectionContextService.capture()
  }

  func stopCurrentWorkflow() {
    activeWorkflow?.stop()
  }

  func resetCurrentWorkflow() {
    activeWorkflow?.reset()
    activeWorkflow = nil
    activePasteTarget = nil
    activeLaunchSource = .manual
    menuBarStatusResetTask?.cancel()
    workflowCleanupTask?.cancel()
    menuBarStatus = .idle
    page = .main
  }

  func enableSecureLocalMode() {
    appSettings.secureLocalModeEnabled = true
    if !selectedLocalModelIsInstalled {
      installSelectedLocalModel()
    }
  }

  func installSelectedLocalModel() {
    guard !isDownloadingLocalModel else { return }

    let modelName = selectedLocalModelName
    localModelDownloadProgress = 0
    localModelDownloadStatusText = "Download startet..."
    localModelDownloadErrorText = nil

    Task {
      do {
        let installedURL = try await LocalTranscriptionService.shared.downloadAndInstall(
          modelName: modelName
        ) { [weak self] progress in
          Task { @MainActor [weak self] in
            guard let self else { return }
            let clampedProgress = min(max(progress, 0), 1)
            self.localModelDownloadProgress = clampedProgress
            self.localModelDownloadStatusText = "Download \(Int(clampedProgress * 100)) %"
          }
        }

        appSettings.selectedLocalTranscriptionModelName = installedURL.lastPathComponent
        appSettings.secureLocalModeEnabled = true
        localModelDownloadProgress = nil
        localModelDownloadStatusText =
          "\(LocalTranscriptionModel.displayName(for: modelName)) ist installiert."
        localModelDownloadErrorText = nil

        try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
      } catch {
        localModelDownloadProgress = nil
        localModelDownloadStatusText = nil
        localModelDownloadErrorText = error.localizedDescription
      }
    }
  }

  func copyToClipboard(_ text: String) {
    writeSensitiveTextToPasteboard(text)
  }

  // MARK: - Auto-Paste

  /// Copies the text, restores focus when needed, then simulates Cmd+V.
  /// The text intentionally remains on the clipboard as a fallback if paste is blocked.
  private func pasteAtCursor(_ text: String, target: PasteTarget? = nil) {
    writeSensitiveTextToPasteboard(text)

    if isPopoverShown {
      NotificationCenter.default.post(name: .dismissPopover, object: nil)
    }

    let trusted = AccessibilityPermissionService.isTrusted(promptIfNeeded: true)
    accessibilityPermissionGranted = trusted
    guard trusted else {
      menuBarStatus = .error(activeWorkflow?.type)
      return
    }

    attemptPasteTrusted(
      target: target,
      attemptsRemaining: Self.pasteRetryInitialAttempts
    )
  }

  private func writeSensitiveTextToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general

    pasteboard.clearContents()
    pasteboard.declareTypes([.string, Self.concealedPasteboardType], owner: nil)
    pasteboard.setString(text, forType: .string)
    pasteboard.setString("", forType: Self.concealedPasteboardType)
  }

  func prepareForPopoverPresentation() {
    refreshAccessibilityPermission()
    lastPopoverPasteTarget = captureCurrentFrontmostApp()
    if let activeWorkflow, activeWorkflow.phase.isActive {
      page = .workflow
    } else if shouldShowOnboarding {
      page = .onboarding
      markOnboardingSeen()
    } else if page == .workflow {
      page = .main
    } else if page == .onboarding {
      page = .main
    }
  }

  func markOnboardingSeen() {
    guard !appSettings.hasSeenOnboarding else { return }
    appSettings.hasSeenOnboarding = true
  }

  // MARK: - API Key Status

  func apiKeyDisplayValue(for key: KeychainKey) -> String {
    guard let value = KeychainService.load(key: key), !value.isEmpty else {
      return ""
    }
    if value.count > 8 {
      return String(value.prefix(4))
        + " \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
    }
    return "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
  }

  func hasValue(for key: KeychainKey) -> Bool {
    guard let value = KeychainService.load(key: key) else { return false }
    return !value.isEmpty
  }

  // MARK: - Settings Persistence

  private static let settingsURL: URL = {
    try? AppSupportPaths.ensureAppSupportDirectoryExists()
    return AppSupportPaths.settingsURL
  }()

  private func saveSettings() {
    let container = SettingsContainer(
      app: appSettings,
      transcription: transcriptionSettings,
      textImprovement: textImprovementSettings,
      dampfAblassen: dampfAblassenSettings,
      emojiText: emojiTextSettings
    )
    if let data = try? JSONEncoder().encode(container) {
      try? data.write(to: Self.settingsURL)
    }
  }

  private static func loadAppSettings() -> AppSettings {
    loadContainer()?.app ?? AppSettings()
  }

  private static func loadTranscriptionSettings() -> TranscriptionSettings {
    loadContainer()?.transcription ?? TranscriptionSettings()
  }

  private static func loadTextImprovementSettings() -> TextImprovementSettings {
    loadContainer()?.textImprovement ?? TextImprovementSettings()
  }

  private static func loadDampfAblassenSettings() -> DampfAblassenSettings {
    loadContainer()?.dampfAblassen ?? DampfAblassenSettings()
  }

  private static func loadEmojiTextSettings() -> EmojiTextSettings {
    loadContainer()?.emojiText ?? EmojiTextSettings()
  }

  private static func loadContainer() -> SettingsContainer? {
    guard let data = try? Data(contentsOf: settingsURL) else { return nil }
    return try? JSONDecoder().decode(SettingsContainer.self, from: data)
  }

  func refreshAccessibilityPermission() {
    let trusted = AccessibilityPermissionService.currentStatus()
    accessibilityPermissionGranted = trusted
    // Remember that the grant was ever real, so we can later detect a stale grant
    // (toggle still on in System Settings but AXIsProcessTrusted() == false after a rebuild).
    if trusted, !appSettings.hadAccessibilityGrant {
      appSettings.hadAccessibilityGrant = true
    }
  }

  /// True when Accessibility was granted before but is no longer recognized — the classic
  /// stale-grant case after an unsigned/ad-hoc rebuild changes the CDHash. The UI uses this
  /// to surface the "remove + re-add the Blitztext entry" guidance.
  var accessibilityLikelyStale: Bool {
    appSettings.hadAccessibilityGrant && !AccessibilityPermissionService.currentStatus()
  }

  /// Begins observing trust transitions so the UI updates without manual re-checks.
  /// Idempotent; safe to call from app launch.
  func startAccessibilityMonitoring() {
    AccessibilityPermissionService.startMonitoring { [weak self] _ in
      self?.refreshAccessibilityPermission()
    }
  }

  func requestAccessibilityPermission() {
    accessibilityPermissionGranted = AccessibilityPermissionService.requestPermissionPrompt()
    refreshAccessibilityPermission()
    AccessibilityPermissionService.openSystemSettings()
    startBoundedAccessibilityPoll()
  }

  /// Bounded poll: re-checks roughly once per second for up to ~10 seconds and stops early as
  /// soon as the grant is detected. Replaces the previous fixed 1s/3s one-shot re-checks so a
  /// grant that lands a few seconds after the user toggles it is still picked up.
  private func startBoundedAccessibilityPoll(attemptsRemaining: Int = 10) {
    guard attemptsRemaining > 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      self.refreshAccessibilityPermission()
      guard !self.accessibilityPermissionGranted else { return }
      self.startBoundedAccessibilityPoll(attemptsRemaining: attemptsRemaining - 1)
    }
  }

  private func autoSelectFastLocalModelIfNeeded() {
    guard !appSettings.hasAutoSelectedFastLocalModel,
      LocalTranscriptionService.shouldAutoSelectRecommendedFastModel(
        currentModelName: appSettings.selectedLocalTranscriptionModelName
      )
    else {
      return
    }

    appSettings.selectedLocalTranscriptionModelName =
      LocalTranscriptionService.recommendedFastModelName
    appSettings.hasAutoSelectedFastLocalModel = true
  }

  private func prewarmLocalTranscriptionIfNeeded() {
    guard appSettings.secureLocalModeEnabled,
      LocalTranscriptionService.isModelInstalled(resolvedLocalModelName)
    else {
      return
    }

    let modelName = resolvedLocalModelName
    Task.detached(priority: .utility) {
      try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
    }
  }

  private func handleWorkflowOutput(_ text: String) {
    pasteAtCursor(text, target: activePasteTarget)
    if activeLaunchSource == .hotkeyBackground {
      page = .main
    }
    scheduleWorkflowCleanup(after: 1.05)
  }

  private func configureWorkflowHandlers<T: Workflow>(_ workflow: T) {
    workflow.onOutput = { [weak self] text in
      self?.handleWorkflowOutput(text)
    }
    workflow.onPhaseChange = { [weak self, weak workflow] phase in
      guard let self, let workflow else { return }
      self.handleWorkflowPhaseChange(phase, workflow: workflow)
    }
    // Wire archiving/Memory-folding ONLY when the archive is enabled, so disabled == zero I/O.
    if appSettings.archiveEnabled {
      workflow.onRun = { [weak self] record in
        self?.handleWorkflowRun(record)
      }
    }
  }

  /// Persists the run to the text archive and folds it into the Memory candidate index
  /// (incrementally, off the main actor). Both are opt-in; this only runs when wired above.
  private func handleWorkflowRun(_ record: ArchiveRunRecord) {
    archiveStore.append(record)
    if appSettings.memoryContextEnabled {
      memoryCoordinator.ingest(rawTranscript: record.rawTranscript, date: record.date)
    }
  }

  private func handleWorkflowPhaseChange(_ phase: WorkflowPhase, workflow: any Workflow) {
    menuBarStatusResetTask?.cancel()

    switch phase {
    case .idle:
      if activeWorkflow == nil {
        menuBarStatus = .idle
      }

    case .running:
      menuBarStatus =
        workflow.isRecording
        ? .recording(workflow.type)
        : .processing(workflow.type)

    case .done:
      menuBarStatus = .success(workflow.type)

    case .error:
      menuBarStatus = .error(workflow.type)
      if activeLaunchSource == .hotkeyBackground {
        activeWorkflow = nil
        activePasteTarget = nil
        page = .main
      }
      scheduleMenuBarStatusReset(after: 1.6)
    }
  }

  private func scheduleWorkflowCleanup(after delay: TimeInterval) {
    guard let workflow = activeWorkflow else { return }

    workflowCleanupTask?.cancel()
    let workflowID = ObjectIdentifier(workflow)

    workflowCleanupTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard let self, let activeWorkflow = self.activeWorkflow else { return }
      guard ObjectIdentifier(activeWorkflow) == workflowID else { return }

      activeWorkflow.reset()
      self.activeWorkflow = nil
      self.activePasteTarget = nil
      self.activeLaunchSource = .manual
      if !self.isPopoverShown {
        self.page = .main
      }
      self.menuBarStatus = .idle
    }
  }

  private func scheduleMenuBarStatusReset(after delay: TimeInterval) {
    menuBarStatusResetTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard let self else { return }
      if self.activeWorkflow == nil || !(self.activeWorkflow?.phase.isActive ?? false) {
        self.menuBarStatus = .idle
      }
    }
  }

  private func capturePasteTarget(for source: WorkflowLaunchSource) -> PasteTarget? {
    switch source {
    case .manual:
      return lastPopoverPasteTarget
    case .hotkeyBackground:
      return captureCurrentFrontmostApp()
    }
  }

  private func attemptPasteTrusted(
    target: PasteTarget?,
    attemptsRemaining: Int
  ) {
    let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

    if let target {
      if frontmostPid == target.processIdentifier {
        performPaste()
        return
      }

      target.application.activate(options: [])
    } else {
      return
    }

    guard attemptsRemaining > 0 else {
      return
    }

    let delay: TimeInterval
    switch attemptsRemaining {
    case 16...:
      delay = 0.015
    case 8...15:
      delay = 0.025
    default:
      delay = 0.04
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.attemptPasteTrusted(
        target: target,
        attemptsRemaining: attemptsRemaining - 1
      )
    }
  }

  private func performPaste() {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }

  private func captureCurrentFrontmostApp() -> PasteTarget? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

    let ownPid = NSRunningApplication.current.processIdentifier
    guard app.processIdentifier != ownPid else { return nil }

    return PasteTarget(
      bundleIdentifier: app.bundleIdentifier,
      processIdentifier: app.processIdentifier,
      application: app
    )
  }
}

private struct SettingsContainer: Codable {
  var app: AppSettings?
  var transcription: TranscriptionSettings
  var textImprovement: TextImprovementSettings
  var dampfAblassen: DampfAblassenSettings?
  var emojiText: EmojiTextSettings?
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
  static let dismissPopover = Notification.Name("dismissPopover")
}

private struct PasteTarget {
  let bundleIdentifier: String?
  let processIdentifier: pid_t
  let application: NSRunningApplication
}
