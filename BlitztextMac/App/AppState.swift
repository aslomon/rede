import AppKit
import Observation
import SwiftUI
import os

private let statusLogger = Logger(subsystem: "app.blitztext.mac", category: "WorkflowStatus")

enum PopoverPage: Equatable {
  case main
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
  /// True for the current finished run when auto-paste could NOT be performed (no paste target, or
  /// the focus race was lost). The text still sits on the clipboard, so the result view tells the
  /// user to paste manually (⌘V) instead of falsely claiming "Eingefügt". Reset on each new run.
  var lastRunWasCopyOnly = false
  /// Set when the most recent rewrite ran on a DIFFERENT model than requested (a silent fallback,
  /// e.g. chosen gpt-5.4 unavailable → gpt-4o-mini). One quiet German line, shown in the result
  /// area so the quality drop is visible. Cleared at the start of each new run. See B6.
  var lastRewriteFallbackNote: String?
  /// The most recent run's error message. Set right before the `.error` status so the floating pill
  /// can show WHY a run failed (esp. background-hotkey runs, which surface no popover). Cleared at
  /// the next recording start.
  private(set) var lastRunErrorMessage: String?
  var localModelDownloadProgress: Double?
  var localModelDownloadStatusText: String?
  var localModelDownloadErrorText: String?
  var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
  /// Invoked when a finished run could NOT be auto-pasted (no Accessibility right / no target /
  /// focus race lost). Carries the dictated text so the floating pill can expand and show it in a
  /// scrollable card with a copy action — instead of the text silently sitting only on the clipboard.
  var onCopyOnlyFallback: ((String) -> Void)?
  /// The dictated text of the current paste attempt, kept so `markCopyOnly` can surface it in the
  /// fallback pill even from the deep retry path (which doesn't carry the text).
  private var currentPasteText: String?

  /// Backs the "Lokale Modelle" management window (Ollama status, installed models, downloads).
  let localModelManager = LocalModelManager()
  private var activeLaunchSource: WorkflowLaunchSource = .manual
  private var activePasteTarget: PasteTarget?
  private var lastPopoverPasteTarget: PasteTarget?
  /// Selection snapshot taken when the popover opens — BEFORE Blitztext activates and steals focus.
  /// Reused for `.manual` starts so reply/edit context isn't read from Blitztext's own window.
  private var pendingPopoverSelection: SelectionContext?
  private var menuBarStatusResetTask: Task<Void, Never>?
  private var workflowCleanupTask: Task<Void, Never>?
  /// The user's clipboard, snapshotted right before auto-paste overwrites it. Restored after a
  /// successful Cmd+V so the previous contents (and any sensitive transcript) don't linger.
  private var pasteboardRestoreSnapshot: PasteboardSnapshot?
  /// Cancellable delayed restore of `pasteboardRestoreSnapshot`. Cancelled if a NEW paste starts
  /// so a second dictation never has its text yanked out from under it by a stale restore.
  private var pasteboardRestoreTask: Task<Void, Never>?
  /// Entprellter (debounced) Settings-Write. Jeder `saveSettings()`-Aufruf bricht den vorigen Task
  /// ab und plant einen neuen, der ~0.4s wartet, bevor er Encode + Disk-Write OFF-Main ausführt.
  /// So fasst schnelles Tippen (z.B. im System-Prompt) viele Mutationen zu EINEM Write zusammen.
  private var pendingSaveTask: Task<Void, Never>?

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

  // MEM-1: on-device "Office Memory" — where dictations land. Metadata only, logged with the
  // archive opt-in. Capture happens at paste-target time; appending happens on run completion.
  let contextLogStore = ContextLogStore()

  // MEM-2: on-device "Verbesserungs-Erkennung" — after a paste, re-read the field later via AX to
  // learn from the user's manual corrections. PRIVACY-SENSITIVE → opt-in, default OFF. Wired only
  // while `improvementDetectionEnabled` (a superset of the archive opt-in).
  let improvementLogStore = ImprovementLogStore()
  /// Snapshot of the just-pasted text + its target, awaiting a single deferred AX re-read.
  private var pendingImprovementSnapshot: ImprovementSnapshot?
  /// The single cancellable deferred re-read. Cancelled whenever a NEW paste/dictation starts so
  /// re-reads never pile up. Re-read is a background follow-up; it never touches the paste path.
  private var improvementRereadTask: Task<Void, Never>?

  // Hotkeys
  let hotkeyService = HotkeyService()

  // Computed
  var isConfigured: Bool {
    KeychainService.isConfigured || !LocalTranscriptionService.installedModels().isEmpty
  }
  var shouldShowOnboarding: Bool {
    !isConfigured && !appSettings.hasCompletedOnboarding
  }

  /// Whether an OpenAI API key is stored — gates the online transcription/rewrite paths.
  var hasOpenAIKey: Bool { hasValue(for: .openAIAPIKey) }

  /// At least one local Whisper model is on disk (speech → text is possible offline).
  var hasAnyTranscriptionEngine: Bool { !LocalTranscriptionService.installedModels().isEmpty }

  /// At least one rewrite engine is usable: the OpenAI key or any installed local Ollama model.
  var hasAnyRewriteEngine: Bool { hasOpenAIKey || !localModelManager.installed.isEmpty }

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
    refreshDefaultPromptsIfNeeded()
    refreshAccessibilityPermission()
    autoSelectFastLocalModelIfNeeded()
    prewarmLocalTranscriptionIfNeeded()
    runMemoryLaunchMaintenanceIfNeeded()
    startAccessibilityMonitoring()
    observeAppActivation()
    observeAppLifecycleForFlush()
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
        // Age-prune the PII logs on activation so retention fires in a long-lived menu-bar process,
        // not only on append/load (R4-DR-retention-timer).
        self?.contextLogStore.pruneExpired()
        self?.improvementLogStore.pruneExpired()
      }
    }
  }

  /// Schreibt ausstehende Settings SOFORT auf die Platte, sobald die App den Fokus verliert oder
  /// beendet wird — so überlebt eine Änderung kurz vor Quit/Blur das 0.4s-Debounce-Fenster.
  /// `willTerminate` läuft synchron auf dem Main-Thread, daher der synchrone `flushSettings()`.
  private func observeAppLifecycleForFlush() {
    let center = NotificationCenter.default
    for name in [
      NSApplication.willResignActiveNotification,
      NSApplication.willTerminateNotification,
    ] {
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.flushSettings() }
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
    // MOST-IMPORTANT-FIRST: explicit user terms, then memory terms best-first
    // (rankedInjectionTerms is best-LAST → reverse).
    let memoryTerms =
      appSettings.memoryContextEnabled
      ? memoryStore.rankedInjectionTerms().reversed().map { $0 } : []
    let merged = Self.mergedTerms(
      userTerms: textImprovementSettings.customTerms, memoryTerms: memoryTerms)
    // Cap to the top-priority terms, then reverse so the best terms sit LAST in the Whisper hint
    // (whisper-1 drops the earliest tokens when the prompt overflows its budget).
    return Array(merged.prefix(MemoryStore.injectionCap)).reversed()
  }

  /// Terms for the REWRITE prompt (TextImprover / DampfAblassen / Emoji): the user's own terms
  /// plus confirmed memory terms in NATURAL (most-important-first) order — NO Whisper cap+reverse.
  /// The chat LLM has no 224-token budget, so capping/reversing would only drop terms pointlessly.
  var effectiveRewriteTerms: [String] {
    let memoryTerms =
      appSettings.memoryContextEnabled
      ? memoryStore.rankedInjectionTerms().reversed().map { $0 } : []
    let merged = Self.mergedTerms(
      userTerms: textImprovementSettings.customTerms, memoryTerms: memoryTerms)
    // Generous cap as a safety bound; the rewrite path has no tight token budget.
    return Array(merged.prefix(Self.rewriteTermsCap))
  }

  /// Generous upper bound for the rewrite-prompt term list (no tight token budget here).
  nonisolated static let rewriteTermsCap = 200

  /// Canonical KNOWN terms for the on-device fuzzy corrector (Eigennamen + confirmed Memory terms),
  /// in natural most-important-first order. Empty when the feature is off → the corrector no-ops.
  /// Uses `effectiveRewriteTerms` (the full uncapped set) so every known term can be snapped to.
  var effectiveFuzzyTerms: [String] {
    appSettings.fuzzyCorrectionEnabled ? effectiveRewriteTerms : []
  }

  /// Dedup + trim, MOST-IMPORTANT-FIRST: explicit user terms first, then memory terms
  /// (already best-first). Pure so it can be unit-tested without an `AppState`.
  nonisolated static func mergedTerms(userTerms: [String], memoryTerms: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    func add(_ term: String) {
      let trimmed = term.trimmingCharacters(in: .whitespaces)
      let key = trimmed.lowercased()
      guard !trimmed.isEmpty, !seen.contains(key) else { return }
      seen.insert(key)
      result.append(trimmed)
    }
    for term in userTerms { add(term) }
    for term in memoryTerms { add(term) }
    return result
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

  // MARK: - Unified vocabulary "recognize" list (Vokabular page)

  /// One merged "richtig erkennen & schreiben" list for the Vokabular page: the user's manual
  /// Eigennamen PLUS the confirmed Memory terms, deduped (manual wins), each tagged with its source.
  /// They were functionally identical and edited in two places — this is the single surface. The
  /// underlying stores (customTerms + memoryStore.confirmed) and the injection pipeline are unchanged.
  struct RecognizeTerm: Identifiable, Hashable {
    let id: String  // lowercased text — stable list identity
    let text: String
    let fromMemory: Bool
    let memoryID: MemoryConfirmedTerm.ID?
  }

  var recognizeTerms: [RecognizeTerm] {
    var seen = Set<String>()
    var result: [RecognizeTerm] = []
    for term in textImprovementSettings.customTerms {
      let trimmed = term.trimmingCharacters(in: .whitespaces)
      let key = trimmed.lowercased()
      guard !trimmed.isEmpty, !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(RecognizeTerm(id: key, text: trimmed, fromMemory: false, memoryID: nil))
    }
    // Confirmed Memory terms only when Memory is on — that's exactly when they're injected, so the
    // list matches reality (turning Memory off hides them; the terms themselves are kept on disk).
    if appSettings.memoryContextEnabled {
      for confirmed in memoryConfirmedTerms {
        let key = confirmed.term.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(
          RecognizeTerm(id: key, text: confirmed.term, fromMemory: true, memoryID: confirmed.id))
      }
    }
    return result
  }

  /// Adds a manual recognize term (Eigenname). Case-insensitive de-dupe against existing manual terms.
  func addRecognizeTerm(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
      !textImprovementSettings.customTerms.contains(where: {
        $0.caseInsensitiveCompare(trimmed) == .orderedSame
      })
    else { return }
    textImprovementSettings.customTerms.append(trimmed)
  }

  /// Removes a recognize term from whichever store owns it (manual list or confirmed Memory).
  func removeRecognizeTerm(_ term: RecognizeTerm) {
    if let memoryID = term.memoryID {
      unconfirmMemory(memoryID)
    } else {
      textImprovementSettings.customTerms.removeAll {
        $0.caseInsensitiveCompare(term.text) == .orderedSame
      }
    }
  }

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

  /// R2-FT-stats: engaging "time saved" aggregate over the EXISTING archive — read-only, no new
  /// capture, no privacy cost. Recomputed live from `archiveStore.entries` (cheap, single pass).
  var dictationStats: DictationStats { DictationStats.compute(from: archiveStore.entries) }

  // MARK: - Office Memory (paste-context log)

  /// Logged dictation destinations, newest first. Metadata only — no dictated text.
  var pasteContexts: [PasteContext] { contextLogStore.contexts }

  /// Category counts across the log, descending — backs the "Du diktierst meist in: …" overview.
  var topPasteContexts: [(PasteContextCategory, Int)] { contextLogStore.topCategories() }

  func clearPasteContexts() { contextLogStore.clear() }

  // MARK: - Improvement detection (MEM-2)

  /// Whether to re-read pasted fields later to learn from manual corrections. Opt-in, default OFF,
  /// and only effective while the archive is on (improvement detection is a superset of archiving).
  var isImprovementDetectionEnabled: Bool {
    get { appSettings.improvementDetectionEnabled && appSettings.archiveEnabled }
    set { appSettings.improvementDetectionEnabled = newValue }
  }

  /// Recorded corrections, newest first — backs the "Verbesserungen" overview.
  var improvementObservations: [ImprovementObservation] { improvementLogStore.observations }

  func clearImprovements() { improvementLogStore.clear() }

  /// MEM-2b: learnable replacement suggestions mined from the recorded corrections — only while
  /// improvement detection is opted in. Excludes pairs already in the dictionary or dismissed.
  var improvementSuggestions: [ImprovementMiner.Suggestion] {
    guard isImprovementDetectionEnabled else { return [] }
    let existingFrom = Set(appSettings.dictationDictionary.replacements.map { $0.from })
    let dismissed = Set(appSettings.dismissedImprovementSuggestionKeys)
    return
      ImprovementMiner
      .suggestions(from: improvementLogStore.observations, existingFrom: existingFrom)
      .filter { !dismissed.contains($0.id) }
  }

  /// Accepts a mined suggestion into the dictation dictionary as a whole-word replacement (skips a
  /// duplicate `from`). The `appSettings` `didSet` persists it; the pair then drops out of the list.
  func acceptImprovementSuggestion(_ suggestion: ImprovementMiner.Suggestion) {
    let existing = appSettings.dictationDictionary.replacements
    let alreadyPresent = existing.contains {
      $0.from.caseInsensitiveCompare(suggestion.from) == .orderedSame
    }
    guard !alreadyPresent else { return }
    // Refuse a fighting inverse pair (dictionary already maps to→from) — it would oscillate text.
    // Dismiss it instead so the unsafe suggestion disappears rather than dead-ending the button.
    let pairs = existing.map { (from: $0.from, to: $0.to) }
    guard
      !ImprovementMiner.conflictsWithExisting(
        from: suggestion.from, to: suggestion.to, existing: pairs)
    else {
      dismissImprovementSuggestion(suggestion)
      return
    }
    appSettings.dictationDictionary.replacements.append(
      DictationReplacement(from: suggestion.from, to: suggestion.to, wholeWord: true))
  }

  /// Permanently hides a suggestion (persisted) without changing the dictionary, so a declined
  /// "Lern-Vorschlag" doesn't reappear on the next launch. De-duped.
  func dismissImprovementSuggestion(_ suggestion: ImprovementMiner.Suggestion) {
    guard !appSettings.dismissedImprovementSuggestionKeys.contains(suggestion.id) else { return }
    appSettings.dismissedImprovementSuggestionKeys.append(suggestion.id)
  }

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
      // Ready only when a local model is actually selected. Otherwise the mode would accept a full
      // dictation and then discard it into a runtime error (data loss). Gating here routes the user
      // to settings BEFORE recording. A down Ollama server still surfaces as a clear runtime error.
      return !appSettings.selectedLocalLLMModelName
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .openai:
      return KeychainService.isConfigured
    }
  }

  // MARK: - Archiv wiederverwenden (FT-3) — re-run a rewrite on a stored transcript

  /// Re-runs the rewrite step on an already-archived raw transcript using a CHOSEN rewrite mode —
  /// no new recording. Reuses the exact provider, prompt and gating of a live run, but never pastes
  /// or captures a live selection. On success optionally appends a fresh archive record.
  /// Errors (empty text, missing key, Ollama down …) surface via `LocalizedError` for the UI.
  func rerunRewrite(
    rawTranscript: String,
    as mode: WorkflowType,
    archiveResult: Bool = true
  ) async -> Result<String, Error> {
    // Fresh re-run: drop any stale model-fallback note before this run can set one (B6).
    lastRewriteFallbackNote = nil
    let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .failure(RerunError.emptyTranscript) }
    guard mode.isRewriteCapable else { return .failure(RerunError.notRewriteCapable) }
    // Same pre-flight gate as recording: route the user to settings instead of losing the run.
    guard rewriteBackendReady(for: mode) else {
      return .failure(RerunError.backendNotReady(resolvedRewriteBackend(for: mode)))
    }

    let config = modeConfig(for: mode)
    let systemPrompt = RewriteReuse.systemPrompt(
      kind: config.kind,
      rewrite: config.rewrite,
      customTerms: effectiveRewriteTerms,
      memory: memoryContext(for: mode)
    )

    do {
      let outcome = try await rewriteProvider(for: mode).rewrite(
        systemPrompt: systemPrompt,
        userText: trimmed,
        temperature: LLMService.defaultRewriteTemperature
      )
      lastRewriteFallbackNote = RewriteModelRegistry.fallbackNote(
        requested: outcome.requestedModelID, used: outcome.usedModelID)
      let cleaned = TranscriptionQualityService.cleanedTranscript(outcome.text)
      guard !cleaned.isEmpty, cleaned != "KEINE_AUFNAHME_ERKANNT" else {
        return .failure(LLMError.noContent)
      }
      if archiveResult, appSettings.archiveEnabled {
        archiveStore.append(
          ArchiveRunRecord(
            mode: mode,
            rawTranscript: trimmed,
            finalText: cleaned,
            backend: rewriteTranscriptionBackend,
            durationSec: 0
          )
        )
      }
      return .success(cleaned)
    } catch {
      return .failure(error)
    }
  }

  /// Pre-flight failures for `rerunRewrite`, surfaced with the same guiding tone as live errors.
  enum RerunError: LocalizedError {
    case emptyTranscript
    case notRewriteCapable
    case backendNotReady(RewriteBackend)

    var errorDescription: String? {
      switch self {
      case .emptyTranscript:
        return "Kein Rohtranskript vorhanden, das umgeschrieben werden könnte."
      case .notRewriteCapable:
        return "Dieser Modus schreibt keinen Text um."
      case .backendNotReady(.openai):
        return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
      case .backendNotReady(.local):
        return
          "Kein lokales Sprachmodell ausgewählt. Wähle in den Einstellungen unter "
          + "„Lokales Sprachmodell (Ollama)“ ein Modell aus."
      }
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

  /// One-time prompt refresh: bumps the E-Mail and Prompt modes from the PREVIOUS curated default to
  /// the current one. A mode whose stored prompt differs from the old default (i.e. the user
  /// customized it) is left untouched. Versioned via `modesSchemaVersion` so it runs exactly once.
  private func refreshDefaultPromptsIfNeeded() {
    let targetVersion = 3
    guard appSettings.modesSchemaVersion < targetVersion else { return }

    /// Bumps a mode whose stored prompt still equals ANY previous curated default to the current one.
    /// A genuinely customized prompt (not in `oldDefaults`) is left untouched.
    func refresh(_ slot: WorkflowType, oldDefaults: [String], newDefault: String) {
      guard var cfg = appSettings.modes[slot.rawValue] else { return }
      if oldDefaults.contains(cfg.rewrite.systemPrompt), cfg.rewrite.systemPrompt != newDefault {
        cfg.rewrite.systemPrompt = newDefault
        appSettings.modes[slot.rawValue] = cfg
      }
    }

    refresh(
      .textImprover, oldDefaults: [ModeDefaults.legacyEmailSystemPrompt],
      newDefault: ModeDefaults.emailSystemPrompt)
    refresh(
      .dampfAblassen,
      oldDefaults: [
        ModeDefaults.legacyPromptCraftSystemPrompt, ModeDefaults.legacyPromptCraftSystemPromptV2,
      ],
      newDefault: ModeDefaults.promptCraftSystemPrompt)

    appSettings.modesSchemaVersion = targetVersion
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

  /// Starts a workflow from a tap inside the popover. Keeps `source: .manual` so the paste target
  /// captured when the popover opened (the app that was frontmost before Blitztext took focus) is
  /// preserved, then dismisses the popover so ONLY the floating pill indicates recording.
  func startWorkflowFromPopover(_ type: WorkflowType) {
    startWorkflow(type, source: .manual)
    // Only dismiss when a workflow actually started — an unavailable mode routes to .settings and
    // must keep the popover open there.
    guard let active = activeWorkflow, active.type == type else { return }
    // An immediate error (e.g. empty selection for "Auswahl bearbeiten") must stay VISIBLE in the
    // popover so the user sees the guidance — only a genuinely running workflow hands off to the pill.
    if case .error = active.phase {
      page = .workflow
      return
    }
    guard active.phase.isActive else { return }
    page = .main
    if isPopoverShown {
      NotificationCenter.default.post(name: .dismissPopover, object: nil)
    }
  }

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
    // Fresh run: drop any stale model-fallback note before a new rewrite can set one (B6).
    lastRewriteFallbackNote = nil
    activeLaunchSource = source
    activePasteTarget = capturePasteTarget(for: source)
    let selection = captureSelectionContext(for: type, source: source)

    switch type {
    case .transcription:
      let workflow = TranscriptionWorkflow(
        customTerms: effectiveCustomTerms,
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
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
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
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
        rewriteTerms: effectiveRewriteTerms,
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
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
        rewriteTerms: effectiveRewriteTerms,
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
        language: transcriptionSettings.language,
        backend: rewriteTranscriptionBackend,
        localModelName: selectedLocalModelName,
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
        rewriteTerms: effectiveRewriteTerms,
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
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
  /// For `.manual` (popover) starts the live frontmost app is Blitztext itself, so we use the
  /// snapshot taken in `prepareForPopoverPresentation` before activation; hotkey/background starts
  /// can capture live because Blitztext (`.accessory`) never steals focus there.
  private func captureSelectionContext(for type: WorkflowType, source: WorkflowLaunchSource)
    -> SelectionContext?
  {
    // Only the E-Mail mode exposes the reply-context control today.
    guard type == .textImprover else { return nil }
    guard modeConfig(for: type).rewrite.replyContextMode != .off else { return nil }
    return source == .manual ? pendingPopoverSelection : SelectionContextService.capture()
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
    // Fresh run: assume a real paste until a no-paste path proves otherwise.
    lastRunWasCopyOnly = false
    currentPasteText = text
    // A new paste/dictation starts: cancel any pending improvement re-read so they never pile up.
    cancelPendingImprovementReread()
    // Stage the improvement candidate (opt-in). Armed only on the success path (`performPaste`).
    pendingImprovementSnapshot = makeImprovementSnapshot(text: text, target: target)
    // A new paste starts: cancel any pending clipboard restore from a previous dictation so it
    // can't race in and yank THIS text off the pasteboard before the target consumes it.
    pasteboardRestoreTask?.cancel()
    pasteboardRestoreTask = nil
    // Snapshot the user's current clipboard BEFORE we overwrite it — restored only on the
    // success path (after the Cmd+V actually fires). Empty snapshots are skipped at restore time.
    pasteboardRestoreSnapshot = PasteboardSnapshot.capture(from: .general)

    writeSensitiveTextToPasteboard(text)

    if isPopoverShown {
      NotificationCenter.default.post(name: .dismissPopover, object: nil)
    }

    let trusted = AccessibilityPermissionService.isTrusted(promptIfNeeded: true)
    accessibilityPermissionGranted = trusted
    guard trusted else {
      // No Accessibility right → we can't synthesize ⌘V. Don't just flash red: keep the text on the
      // clipboard and surface it in the fallback pill so the dictation is never lost, plus guide the
      // user to fix the permission (the common ad-hoc-signing / stale-grant case).
      lastRunErrorMessage =
        "Bedienungshilfen-Recht fehlt — Text kopiert, mit ⌘V einfügen. In Systemeinstellungen → Bedienungshilfen erneut erlauben."
      markCopyOnly()
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
    // Snapshot the selection now, while the user's app is still frontmost (showPopover activates
    // Blitztext right after this). Only when the E-Mail mode wants reply/edit context.
    pendingPopoverSelection =
      modeConfig(for: .textImprover).rewrite.replyContextMode != .off
      ? SelectionContextService.capture()
      : nil
    if let activeWorkflow, activeWorkflow.phase.isActive {
      page = .workflow
    } else if page == .workflow {
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

  /// Baut einen Sendable-Snapshot der aktuellen Settings auf dem MainActor (reine Value-Types,
  /// also ein echter Wert-Kopie). Der Snapshot wandert anschließend in den Hintergrund-Write.
  private func makeSettingsSnapshot() -> SettingsContainer {
    SettingsContainer(
      app: appSettings,
      transcription: transcriptionSettings,
      textImprovement: textImprovementSettings,
      dampfAblassen: dampfAblassenSettings,
      emojiText: emojiTextSettings
    )
  }

  /// Entprellter Persist: bricht den ausstehenden Write ab und plant einen neuen, der ~0.4s wartet
  /// (abbrechbar) und dann den Snapshot OFF-Main encodiert + atomar mit 0600 schreibt. So wird
  /// pro Tipp-Burst nur EINMAL auf die Platte geschrieben, statt bei jedem Tastendruck.
  private func saveSettings() {
    pendingSaveTask?.cancel()
    let snapshot = makeSettingsSnapshot()
    let url = Self.settingsURL
    pendingSaveTask = Task.detached(priority: .utility) { [weak self] in
      try? await Task.sleep(for: .seconds(0.4))
      guard !Task.isCancelled else { return }
      Self.persistSnapshot(snapshot, to: url)
      await MainActor.run { self?.pendingSaveTask = nil }
    }
  }

  /// Schreibt SOFORT und SYNCHRON und bricht den Debounce ab — für den Fall, dass die App den Fokus
  /// verliert oder beendet wird, BEVOR das 0.4s-Fenster abläuft. Synchron, weil `willTerminate` die
  /// App beenden kann, bevor ein async Task abschließt — so geht keine Settings-Änderung verloren.
  private func flushSettings() {
    pendingSaveTask?.cancel()
    pendingSaveTask = nil
    Self.persistSnapshot(makeSettingsSnapshot(), to: Self.settingsURL)
  }

  /// Encode + atomarer 0600-Write via `SecureFileWriter`. `nonisolated`, damit es vom Debounce-Task
  /// off-main aufgerufen werden kann; der Snapshot ist ein Sendable-Wert (Daten-Race-frei). Encode
  /// + Write sind reine CPU/IO ohne Aktor-Bezug, also sicher außerhalb des MainActors.
  private nonisolated static func persistSnapshot(
    _ snapshot: SettingsContainer, to url: URL
  ) {
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    try? SecureFileWriter.write(data, to: url)
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
    wireRewriteFallbackNote(workflow)
  }

  /// Surfaces the model-fallback note for the rewrite workflows only (transcription never rewrites).
  private func wireRewriteFallbackNote<T: Workflow>(_ workflow: T) {
    let handler: WorkflowRewriteFallbackHandler = { [weak self] note in
      self?.lastRewriteFallbackNote = note
    }
    switch workflow {
    case let workflow as TextImprovementWorkflow: workflow.onRewriteFallback = handler
    case let workflow as DampfAblassenWorkflow: workflow.onRewriteFallback = handler
    case let workflow as EmojiTextWorkflow: workflow.onRewriteFallback = handler
    default: break
    }
  }

  /// Persists the run to the text archive, folds it into the Memory candidate index
  /// (incrementally, off the main actor), and logs WHERE it landed (Office Memory). All opt-in;
  /// this only runs when wired above (i.e. while the archive is enabled).
  private func handleWorkflowRun(_ record: ArchiveRunRecord) {
    // Sensitive-Field Guard: a run pasted into a secure/password field must leave NO trace — its
    // text (possibly a password) is never archived, context-logged or folded into Memory.
    guard !(activePasteTarget?.isSecureField ?? false) else {
      statusLogger.debug("Secure paste target → skipping archive/context/memory for this run.")
      return
    }
    archiveStore.append(record)
    logPasteContext(for: record)
    if appSettings.memoryContextEnabled {
      memoryCoordinator.ingest(rawTranscript: record.rawTranscript, date: record.date)
    }
  }

  /// Records the destination of a completed run from the captured paste target. Metadata only —
  /// never the dictated text. Categorized from the target bundle id + focused-element role.
  private func logPasteContext(for record: ArchiveRunRecord) {
    let target = activePasteTarget
    let category = PasteContextCategory.categorize(
      bundleID: target?.bundleIdentifier, role: target?.elementRole,
      windowTitle: target?.windowTitle)
    let context = PasteContext(
      date: record.date,
      appBundleID: target?.bundleIdentifier,
      appName: target?.appName,
      windowTitle: target?.windowTitle,
      elementRole: target?.elementRole,
      category: category,
      mode: record.mode,
      charCount: record.finalText.count
    )
    contextLogStore.append(context)
  }

  private func handleWorkflowPhaseChange(_ phase: WorkflowPhase, workflow: any Workflow) {
    menuBarStatusResetTask?.cancel()

    switch phase {
    case .idle:
      if activeWorkflow == nil {
        menuBarStatus = .idle
      }

    case .running:
      if workflow.isRecording { lastRunErrorMessage = nil }  // clear stale error at run start
      menuBarStatus =
        workflow.isRecording
        ? .recording(workflow.type)
        : .processing(workflow.type)
      // Earcon at recording start only (the transcribing `.running` has isRecording == false).
      if workflow.isRecording { playEarcon(.start) }
      statusLogger.debug(
        "phase=.running isRecording=\(workflow.isRecording) → status=\(String(describing: self.menuBarStatus), privacy: .public)"
      )

    case .done:
      menuBarStatus = .success(workflow.type)
      playEarcon(.done)

    case .error(let message):
      // Stash the message BEFORE the status change so the pill (driven by the status) can show it —
      // crucial for background-hotkey runs, which otherwise reset the page and swallow the text.
      lastRunErrorMessage = message
      menuBarStatus = .error(workflow.type)
      // A no-speech take is benign — don't punish it with the harsh error earcon; stay silent.
      if message != TranscriptionQualityService.noSpeechMessage { playEarcon(.error) }
      if activeLaunchSource == .hotkeyBackground {
        activeWorkflow = nil
        activePasteTarget = nil
        page = .main
      }
      scheduleMenuBarStatusReset(after: 1.6)
    }
  }

  /// Plays an optional audio cue, but only when the user opted into sound feedback.
  private func playEarcon(_ event: EarconPlayer.Event) {
    guard appSettings.soundFeedbackEnabled else { return }
    EarconPlayer.play(event)
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

      // `.activateIgnoringOtherApps` is required: a background .accessory app's plain activate() is
      // unreliable on recent macOS, so the target never comes frontmost in time and the run silently
      // degrades to copy-only even with Accessibility granted.
      target.application.activate(options: [.activateIgnoringOtherApps])
    } else {
      // No paste target (e.g. nothing focusable was frontmost): the text is on the clipboard but
      // we can't paste it. Tell the user instead of silently claiming success.
      markCopyOnly()
      return
    }

    guard attemptsRemaining > 0 else {
      // Focus race lost — the target never came frontmost in time. The text is still on the
      // clipboard; surface the "kopiert — ⌘V" hint so the user knows it wasn't lost.
      markCopyOnly()
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

  /// No paste happened (no target / focus race lost). Flags the run as copy-only so the result
  /// view shows "kopiert — ⌘V", and drops the restore snapshot so OUR text stays on the clipboard
  /// as the fallback the user can paste manually (the success path is the only one that restores).
  private func markCopyOnly() {
    lastRunWasCopyOnly = true
    pasteboardRestoreSnapshot = nil
    // Surface the dictated text in the expanding fallback pill so it's never silently stuck on the
    // clipboard — the user can read it, copy it, and paste it wherever they want.
    if let text = currentPasteText, !text.isEmpty {
      onCopyOnlyFallback?(text)
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

    // Only the success path reaches here, so this is the only place we restore the user's
    // clipboard — failed/blocked pastes deliberately leave our text on the board as a fallback.
    scheduleClipboardRestore()

    // The paste landed: arm the single deferred AX re-read to learn from later manual corrections.
    // Opt-in; a no-op when improvement detection is off. Never blocks/alters the paste above.
    scheduleImprovementReread()
  }

  /// Restores the pre-paste clipboard snapshot after a short delay so the target app has time to
  /// consume our pasted text first (the Cmd+V is async; restoring immediately could swap the
  /// pasteboard out before the paste lands). Cancellable so a new dictation supersedes it.
  private func scheduleClipboardRestore() {
    guard let snapshot = pasteboardRestoreSnapshot, !snapshot.isEmpty else {
      pasteboardRestoreSnapshot = nil
      return
    }
    pasteboardRestoreSnapshot = nil
    pasteboardRestoreTask?.cancel()
    pasteboardRestoreTask = Task { @MainActor [weak self] in
      // ~0.75s: long enough for typical target apps to read the pasteboard on Cmd+V, short
      // enough that the user's clipboard is back almost immediately.
      try? await Task.sleep(for: .milliseconds(750))
      guard !Task.isCancelled, let self else { return }
      snapshot.restore(to: .general)
      self.pasteboardRestoreTask = nil
    }
  }

  // MARK: - Improvement detection (MEM-2) — deferred AX re-read

  /// Stages the just-pasted text + target for a later re-read, but ONLY when improvement detection
  /// is opted in AND the target carries a usable bundle id / pid. `nil` (skip) otherwise — disabled
  /// means we never even build a snapshot, so the feature is truly inert when off.
  private func makeImprovementSnapshot(text: String, target: PasteTarget?) -> ImprovementSnapshot? {
    guard isImprovementDetectionEnabled else { return nil }
    guard let target else { return nil }
    // Sensitive-Field Guard: never re-read (and thus never store) the contents of a secure field.
    guard !target.isSecureField else { return nil }
    let inserted = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !inserted.isEmpty else { return nil }
    return ImprovementSnapshot(
      insertedText: inserted,
      processIdentifier: target.processIdentifier,
      bundleIdentifier: target.bundleIdentifier,
      appName: target.appName,
      mode: activeWorkflow?.type ?? .transcription
    )
  }

  /// Cancels the pending deferred re-read (if any) and drops the staged snapshot. Called whenever a
  /// new paste/dictation starts so re-reads never accumulate.
  private func cancelPendingImprovementReread() {
    improvementRereadTask?.cancel()
    improvementRereadTask = nil
    pendingImprovementSnapshot = nil
  }

  /// Arms the SINGLE deferred re-read for the staged snapshot. Runs ~10s later (a background
  /// follow-up — it never blocks or alters the paste). Cancelled by the next paste/dictation.
  private func scheduleImprovementReread() {
    guard let snapshot = pendingImprovementSnapshot else { return }
    pendingImprovementSnapshot = nil
    improvementRereadTask?.cancel()
    improvementRereadTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(10))
      guard !Task.isCancelled, let self else { return }
      self.performImprovementReread(snapshot)
      self.improvementRereadTask = nil
    }
  }

  /// Re-reads the target field's current value via AX and records an observation when our inserted
  /// text is locatable (verbatim or clearly edited in place). Fully guarded: the app must still be
  /// alive and the focused element must still be a text field — any nil/failure silently skips.
  private func performImprovementReread(_ snapshot: ImprovementSnapshot) {
    guard isImprovementDetectionEnabled else { return }
    // Re-verify the PID still belongs to the SAME app we pasted into. A PID is recycled by the OS
    // once a process exits, so over the ~10s defer window the target could have quit and an unrelated
    // app inherited its pid — re-reading then would log a false correction from a foreign field.
    // Require a live app whose bundle id matches the snapshot's; bail (skip) on any mismatch or nil.
    guard
      let liveApp = NSRunningApplication(processIdentifier: snapshot.processIdentifier),
      let liveBundleID = liveApp.bundleIdentifier,
      liveBundleID == snapshot.bundleIdentifier
    else { return }
    guard let fieldValue = PasteContextAXReader.readFocusedValue(pid: snapshot.processIdentifier)
    else { return }
    guard
      let result = ImprovementDiff.observe(
        inserted: snapshot.insertedText, fieldValue: fieldValue)
    else { return }

    let observation = ImprovementObservation(
      date: Date(),
      appBundleID: snapshot.bundleIdentifier,
      appName: snapshot.appName,
      mode: snapshot.mode.rawValue,
      inserted: snapshot.insertedText,
      finalText: result.finalText,
      changed: result.changed
    )
    improvementLogStore.append(observation)
  }

  private func captureCurrentFrontmostApp() -> PasteTarget? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

    let ownPid = NSRunningApplication.current.processIdentifier
    guard app.processIdentifier != ownPid else { return nil }

    // Office-Memory metadata: read the window title + focused-element role NOW, while the target
    // is still frontmost and BEFORE Blitztext activates. Best-effort; all nil if Accessibility off.
    let context = PasteContextAXReader.read(pid: app.processIdentifier)
    return PasteTarget(
      bundleIdentifier: app.bundleIdentifier,
      processIdentifier: app.processIdentifier,
      application: app,
      appName: app.localizedName,
      windowTitle: context.windowTitle,
      elementRole: context.elementRole,
      isSecureField: context.isSecureField
    )
  }
}

private struct SettingsContainer: Codable, Sendable {
  var app: AppSettings?
  var transcription: TranscriptionSettings
  var textImprovement: TextImprovementSettings
  var dampfAblassen: DampfAblassenSettings?
  var emojiText: EmojiTextSettings?
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
  static let dismissPopover = Notification.Name("dismissPopover")
  /// Posted by settings to open the standalone "Lokale Modelle" management window.
  static let openLocalModelsWindow = Notification.Name("openLocalModelsWindow")
  /// Posted by the empty-state nudges and the "Einrichtung erneut starten" action to open the
  /// standalone first-run onboarding wizard window.
  static let openOnboardingWindow = Notification.Name("openOnboardingWindow")
  /// Posted by the archive tab to open the standalone "Transkriptions-Archiv" window.
  static let openArchiveWindow = Notification.Name("openArchiveWindow")
}

private struct PasteTarget {
  let bundleIdentifier: String?
  let processIdentifier: pid_t
  let application: NSRunningApplication
  /// Office-Memory metadata, read via AX at target-capture time (before Blitztext activates) so
  /// the actual Cmd+V paste stays latency-free. All nil when Accessibility is off / unavailable.
  let appName: String?
  let windowTitle: String?
  let elementRole: String?
  /// True when the focused element is a secure/password field. Such a run is treated as sensitive:
  /// its text is NOT archived, NOT context-logged and NOT improvement-tracked (R4-FT-secure-guard).
  let isSecureField: Bool
}

/// Staged candidate for the MEM-2 deferred AX re-read: the text Blitztext inserted plus the target
/// it landed in. Built only when improvement detection is opted in; armed on the paste success path.
private struct ImprovementSnapshot {
  let insertedText: String
  let processIdentifier: pid_t
  let bundleIdentifier: String?
  let appName: String?
  let mode: WorkflowType
}
