import AppKit
import Observation
import SwiftUI
import os

private let statusLogger = Logger(subsystem: "app.rede.mac", category: "WorkflowStatus")
private let contextCaptureLogger = Logger(
  subsystem: "app.rede.mac", category: "ContextCapture")

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
  var settingsTabSelection = 0
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
  /// True while a local Whisper model is loading/prewarming into memory. Large models take minutes
  /// on their first load (ANE compilation); surfacing this keeps that wait from reading as a hang or
  /// error, and lets the UI tell the user the engine is getting ready.
  private(set) var localModelPreparing = false
  /// Tracks the in-flight prewarm so switching models cancels the previous one's bookkeeping.
  @ObservationIgnored private var localModelPrewarmTask: Task<Void, Never>?
  var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
  /// Invoked when a finished run could NOT be auto-pasted (no Accessibility right / no target /
  /// focus race lost). Carries the dictated text so the floating pill can expand and show it in a
  /// scrollable card with a copy action — instead of the text silently sitting only on the clipboard.
  var onCopyOnlyFallback: ((String) -> Void)?
  var onVariantChoice: ((PendingRewriteVariants) -> Void)?
  /// The dictated text of the current paste attempt, kept so `markCopyOnly` can surface it in the
  /// fallback pill even from the deep retry path (which doesn't carry the text).
  private var currentPasteText: String?
  private var pendingVariantChoice: PendingRewriteVariants?

  /// Backs the "Lokale Modelle" management window (Ollama status, installed models, downloads).
  let localModelManager = LocalModelManager()
  private var activeLaunchSource: WorkflowLaunchSource = .manual
  private var activeModeID: ModeConfig.ID?
  private var activePasteTarget: PasteTarget?
  private var lastPopoverPasteTarget: PasteTarget?
  /// Selection snapshot taken when the popover opens — BEFORE rede activates and steals focus.
  /// Reused for `.manual` starts so reply/edit context isn't read from rede's own window.
  private var pendingPopoverSelection: SelectionContext?
  /// Automatic field-context snapshot taken next to `pendingPopoverSelection`, before the popover
  /// activates rede. In-memory only; it is consumed by the next manual rewrite run.
  private var pendingPopoverAutomaticContext: AutomaticRewriteContext?
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
      if oldValue.selectedLocalTranscriptionModelName
        != appSettings.selectedLocalTranscriptionModelName
      {
        // The user explicitly switched the Whisper model — preload the new one now (even outside
        // secure-local mode), so its slow first load happens here with visible status instead of
        // blocking the next dictation.
        prepareLocalModel(resolvedLocalModelName)
      } else {
        prewarmLocalTranscriptionIfNeeded()
      }
      reloadHotkeys()
      applyRecordingSettings()
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
  let emailSemanticMemoryStore = EmailSemanticMemoryStore()
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

  // In-app updates (Sparkle, gated behind SPARKLE_ENABLED). Created at launch so the daily
  // scheduled check arms immediately; UI goes through this service, never through Sparkle types.
  let updateService = UpdateService()

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

  /// At least one rewrite engine is usable: the OpenAI key or an installed local llama.cpp model.
  var hasAnyRewriteEngine: Bool { hasOpenAIKey || !localModelManager.llamaCppInstalled.isEmpty }

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
    applyRecordingSettings()
    reloadHotkeys()
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

  /// Syncs the recording-related globals on `AudioRecorder` from the persisted settings. The cap is
  /// clamped to a sane floor so a corrupt/zero value can never disable recording. Called at launch
  /// and on every settings change; the recorder reads these when it arms the next recording.
  private func applyRecordingSettings() {
    let minutes = max(1, appSettings.maxDictationMinutes)
    AudioRecorder.maxRecordingDuration = TimeInterval(minutes * 60)
    AudioRecorder.silenceTrimmingEnabled = appSettings.silenceTrimmingEnabled
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
  /// Recurring domain terms can auto-promote into the visible vocabulary.
  func recomputeMemory() {
    Task { await memoryCoordinator.recomputeMemory() }
  }

  /// Confirmed learned terms + the user's manual terms, ranked and capped, for the Whisper hint.
  /// Once Memory learns a term it becomes a normal vocabulary term, so it stays active even when
  /// the Memory master is later turned off. Remove it from "Begriffe" to stop using it.
  var effectiveCustomTerms: [String] {
    // MOST-IMPORTANT-FIRST: explicit user terms, then memory terms best-first
    // (rankedInjectionTerms is best-LAST → reverse).
    let memoryTerms = memoryStore.rankedInjectionTerms().reversed().map { $0 }
    let merged = Self.mergedTerms(
      userTerms: stableUserTerms + textImprovementSettings.customTerms, memoryTerms: memoryTerms)
    // Cap to the top-priority terms, then reverse so the best terms sit LAST in the Whisper hint
    // (whisper-1 drops the earliest tokens when the prompt overflows its budget).
    return Array(merged.prefix(MemoryStore.injectionCap)).reversed()
  }

  /// Terms for the REWRITE prompt (TextImprover / DampfAblassen / Emoji): the user's own terms
  /// plus confirmed learned terms in NATURAL (most-important-first) order — NO Whisper cap+reverse.
  /// The chat LLM has no 224-token budget, so capping/reversing would only drop terms pointlessly.
  var effectiveRewriteTerms: [String] {
    let memoryTerms = memoryStore.rankedInjectionTerms().reversed().map { $0 }
    let merged = Self.mergedTerms(
      userTerms: stableUserTerms + textImprovementSettings.customTerms, memoryTerms: memoryTerms)
    // Generous cap as a safety bound; the rewrite path has no tight token budget.
    return Array(merged.prefix(Self.rewriteTermsCap))
  }

  /// Generous upper bound for the rewrite-prompt term list (no tight token budget here).
  nonisolated static let rewriteTermsCap = 200

  var userIdentityContext: UserIdentityContext? {
    let name = appSettings.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    return UserIdentityContext(displayName: name)
  }

  private var stableUserTerms: [String] {
    let name = appSettings.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return [] }
    return [name]
  }

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
    memoryContext(for: modeConfig(for: type))
  }

  func memoryContext(for config: ModeConfig) -> MemoryContext? {
    guard appSettings.memoryContextEnabled else { return nil }
    guard config.rewrite.useMemoryContext else { return nil }
    let context = memoryStore.context
    return context.isEmpty ? nil : context
  }

  // MARK: - Memory curation (changes the injected set)

  /// Lower-confidence candidates retained for diagnostics/legacy UI; strong candidates auto-learn.
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
  /// terms PLUS automatically learned Memory terms, deduped (manual wins), each tagged with its
  /// source.
  struct RecognizeTerm: Identifiable, Hashable {
    let id: String  // lowercased text — stable list identity
    let text: String
    let fromMemory: Bool
    let memoryID: MemoryConfirmedTerm.ID?
    let memoryLemma: String?
  }

  var recognizeTerms: [RecognizeTerm] {
    var seen = Set<String>()
    var result: [RecognizeTerm] = []
    for term in textImprovementSettings.customTerms {
      let trimmed = term.trimmingCharacters(in: .whitespaces)
      let key = trimmed.lowercased()
      guard !trimmed.isEmpty, !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(
        RecognizeTerm(
          id: key, text: trimmed, fromMemory: false, memoryID: nil, memoryLemma: nil))
    }
    // Confirmed Memory terms are now normal vocabulary: Memory can be off while already-learned
    // terms still help transcription/rewrite spelling. Remove one here to deny it permanently.
    for confirmed in memoryConfirmedTerms {
      let key = confirmed.term.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(
        RecognizeTerm(
          id: key, text: confirmed.term, fromMemory: true, memoryID: confirmed.id,
          memoryLemma: confirmed.lemma))
    }
    // Cap the whole visible list (manual + learned) to a focused set. Manual terms come first, so
    // they are kept; auto-learned terms fill the remaining slots up to the cap.
    return Array(result.prefix(MemoryStore.injectionCap))
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

  /// Removes a recognize term from whichever store owns it. Learned terms are denylisted so they do
  /// not immediately auto-learn again.
  func removeRecognizeTerm(_ term: RecognizeTerm) {
    if term.memoryID != nil {
      memoryStore.deny(term: term.text)
      if let lemma = term.memoryLemma, lemma.caseInsensitiveCompare(term.text) != .orderedSame {
        memoryStore.deny(term: lemma)
      }
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

  var isSemanticEmailMemoryEnabled: Bool {
    get { appSettings.semanticEmailMemoryEnabled }
    set {
      appSettings.semanticEmailMemoryEnabled = newValue
      if newValue { prepareSemanticEmailMemory() }
    }
  }

  var selectedEmbeddingModelName: String {
    appSettings.selectedEmbeddingModelName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var semanticEmailEmbeddingIsReady: Bool {
    !selectedEmbeddingModelName.isEmpty
      && localModelManager.isLlamaCppEmbeddingInstalled(selectedEmbeddingModelName)
  }

  var semanticEmailEmbeddingIsPreparing: Bool {
    !selectedEmbeddingModelName.isEmpty
      && (localModelManager.isRefreshing
        || localModelManager.isDownloadingLlamaCpp(selectedEmbeddingModelName))
  }

  var semanticEmailMemoryIsReady: Bool {
    appSettings.archiveEnabled && appSettings.semanticEmailMemoryEnabled
      && semanticEmailEmbeddingIsReady
  }

  func prepareSemanticEmailMemory() {
    appSettings.archiveEnabled = true
    if selectedEmbeddingModelName.isEmpty {
      appSettings.selectedEmbeddingModelName = LlamaCppEmbeddingProvider.defaultModelID
    }
    guard
      let model = LlamaCppModelCatalog.embeddingModels.first(where: {
        $0.id == selectedEmbeddingModelName
      })
    else { return }
    guard !localModelManager.isLlamaCppEmbeddingInstalled(model.id),
      !localModelManager.isDownloadingLlamaCpp(model.id)
    else { return }
    Task { [weak self] in
      guard let self else { return }
      await self.localModelManager.refresh()
      guard !self.localModelManager.isLlamaCppEmbeddingInstalled(model.id),
        !self.localModelManager.isDownloadingLlamaCpp(model.id)
      else {
        return
      }
      self.localModelManager.downloadLlamaCpp(model)
    }
  }

  var isUnifiedMemoryEnabled: Bool {
    get {
      appSettings.memoryContextEnabled
        || appSettings.semanticEmailMemoryEnabled
        || appSettings.improvementDetectionEnabled
    }
    set {
      appSettings.memoryContextEnabled = newValue
      appSettings.semanticEmailMemoryEnabled = newValue
      if !newValue {
        appSettings.improvementDetectionEnabled = false
      }
      if newValue {
        appSettings.archiveEnabled = true
        runMemoryLaunchMaintenanceIfNeeded()
        prepareSemanticEmailMemory()
      }
    }
  }

  var isMemoryContextEnabled: Bool {
    get { appSettings.memoryContextEnabled }
    set {
      appSettings.memoryContextEnabled = newValue
      if newValue {
        appSettings.archiveEnabled = true
        runMemoryLaunchMaintenanceIfNeeded()
      }
    }
  }

  func clearArchive() { archiveStore.clear() }
  func clearMemory() { memoryStore.clear() }
  func clearEmailSemanticMemory() { emailSemanticMemoryStore.clear() }

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
    set {
      appSettings.improvementDetectionEnabled = newValue
      if newValue { appSettings.archiveEnabled = true }
    }
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

  nonisolated static func orderedModeConfigs(
    modes: [String: ModeConfig],
    modeOrder: [String]
  ) -> [ModeConfig] {
    var seen = Set<String>()
    var result: [ModeConfig] = []

    func append(id: String) {
      guard !seen.contains(id), let mode = modes[id] else { return }
      seen.insert(id)
      result.append(mode)
    }

    for id in modeOrder { append(id: id) }
    for slot in WorkflowType.allCases { append(id: slot.rawValue) }
    for id in modes.keys.sorted() { append(id: id) }

    return result
  }

  nonisolated static func reorderedModeIDs(
    _ modeOrder: [ModeConfig.ID],
    moving id: ModeConfig.ID,
    offset: Int
  ) -> [ModeConfig.ID] {
    guard let currentIndex = modeOrder.firstIndex(of: id) else { return modeOrder }
    let targetIndex = currentIndex + offset
    guard modeOrder.indices.contains(targetIndex) else { return modeOrder }
    var result = modeOrder
    let removed = result.remove(at: currentIndex)
    result.insert(removed, at: targetIndex)
    return result
  }

  var orderedModeConfigs: [ModeConfig] {
    Self.orderedModeConfigs(modes: appSettings.modes, modeOrder: appSettings.modeOrder)
  }

  var mainMenuModeConfigs: [ModeConfig] {
    orderedModeConfigs.filter { $0.slot != .localTranscription }
  }

  var semanticEmailMemoryStatusLabel: String {
    guard appSettings.semanticEmailMemoryEnabled else { return "aus" }
    guard appSettings.archiveEnabled else { return "archiv aus" }
    guard semanticEmailEmbeddingIsReady else {
      return semanticEmailEmbeddingIsPreparing ? "lädt" : "modell fehlt"
    }
    let count = emailSemanticMemoryStore.records.count
    return count == 1 ? "1 eintrag" : "\(count) einträge"
  }

  var unifiedMemoryStatusLabel: String {
    guard isUnifiedMemoryEnabled else { return "aus" }
    if semanticEmailEmbeddingIsPreparing { return "lädt" }
    if appSettings.semanticEmailMemoryEnabled, !semanticEmailEmbeddingIsReady {
      return "modell fehlt"
    }
    let confirmed = memoryConfirmedTerms.count
    let emails = emailSemanticMemoryStore.records.count
    if confirmed == 0, emails == 0 { return "bereit" }
    return "\(confirmed) begriffe · \(emails) E-Mails"
  }

  var effectiveHotkeyConfigs: [ModeConfig.ID: HotkeyConfig] {
    HotkeyRegistry.effectiveConfigs(for: orderedModeConfigs, stored: appSettings.hotkeys)
  }

  var currentActiveModeID: ModeConfig.ID? {
    activeModeID
  }

  func hotkeyLabel(for modeID: ModeConfig.ID) -> String {
    effectiveHotkeyConfigs[modeID]?.label ?? "nicht gesetzt"
  }

  func hotkeyConfig(for modeID: ModeConfig.ID) -> HotkeyConfig {
    effectiveHotkeyConfigs[modeID] ?? HotkeyConfig(modeID: modeID, modifiers: [], isEnabled: false)
  }

  var hotkeyValidationIssues: [HotkeyValidationIssue] {
    HotkeyRegistry.validationIssues(configs: effectiveHotkeyConfigs)
  }

  func hotkeyConflictLabel(for modeID: ModeConfig.ID) -> String? {
    for issue in hotkeyValidationIssues {
      switch issue {
      case .duplicate(let label, let modeIDs) where modeIDs.contains(modeID):
        return "konflikt: \(label) wird mehrfach verwendet."
      default:
        continue
      }
    }
    return nil
  }

  func hotkeyConflictLabel(for candidate: HotkeyConfig, excluding modeID: ModeConfig.ID) -> String?
  {
    HotkeyRegistry.conflictLabel(
      for: candidate,
      excluding: modeID,
      configs: effectiveHotkeyConfigs
    )
  }

  func updateHotkey(id: ModeConfig.ID, _ transform: (inout HotkeyConfig) -> Void) {
    var config = hotkeyConfig(for: id)
    transform(&config)
    appSettings.hotkeys[id] = config
  }

  func setHotkeyRecordingActive(_ isActive: Bool) {
    hotkeyService.isSuspended = isActive
  }

  private func reloadHotkeys() {
    hotkeyService.reload(configs: effectiveHotkeyConfigs)
  }

  func modeConfig(for id: ModeConfig.ID) -> ModeConfig? {
    appSettings.modes[id]
  }

  func modeConfig(for type: WorkflowType) -> ModeConfig {
    appSettings.modes[type.rawValue] ?? .default(for: type)
  }

  func updateMode(id: ModeConfig.ID, _ transform: (inout ModeConfig) -> Void) {
    guard var config = modeConfig(for: id) else { return }
    transform(&config)
    appSettings.modes[id] = config
    if !appSettings.modeOrder.contains(id) {
      appSettings.modeOrder.append(id)
    }
  }

  func updateMode(_ type: WorkflowType, _ transform: (inout ModeConfig) -> Void) {
    var config = modeConfig(for: type)
    transform(&config)
    appSettings.modes[type.rawValue] = config
    if !appSettings.modeOrder.contains(type.rawValue) {
      appSettings.modeOrder.append(type.rawValue)
    }
  }

  func resetMode(_ type: WorkflowType) {
    appSettings.modes[type.rawValue] = .default(for: type)
    if !appSettings.modeOrder.contains(type.rawValue) {
      appSettings.modeOrder.append(type.rawValue)
    }
  }

  func resetMode(id: ModeConfig.ID) {
    guard let existing = modeConfig(for: id) else { return }
    var reset = ModeConfig.default(for: existing.slot)
    reset.modeID = existing.id == existing.slot.rawValue ? nil : existing.id
    appSettings.modes[id] = reset
    if !appSettings.modeOrder.contains(id) {
      appSettings.modeOrder.append(id)
    }
  }

  func duplicateMode(id: ModeConfig.ID) {
    guard let source = modeConfig(for: id) else { return }
    let newID = "mode-\(UUID().uuidString)"
    let duplicate = ModeConfig.duplicate(
      source,
      newID: newID,
      userName: "\(displayName(for: source)) Kopie"
    )
    appSettings.modes[newID] = duplicate
    insertModeID(newID, after: id)
  }

  /// ID of the mode just created via `addMode`, so its card can auto-open in edit mode exactly once.
  var newlyCreatedModeID: ModeConfig.ID?

  func addMode(template: ModeTemplate) {
    let newID = "mode-\(UUID().uuidString)"
    var mode = template.makeMode(id: newID)
    // Name new modes "<base> (neu)" so they're easy to spot next to the existing one.
    mode.userName = "\(mode.userName) (neu)"
    appSettings.modes[newID] = mode
    insertModeID(newID, after: template.slot.rawValue)
    newlyCreatedModeID = newID
    openSettings(tab: 0)
  }

  func openSettings(tab: Int = 0) {
    settingsTabSelection = min(max(tab, 0), 4)
    page = .settings
  }

  func deleteMode(id: ModeConfig.ID) {
    guard let existing = modeConfig(for: id), existing.id != existing.slot.rawValue else { return }
    appSettings.modes.removeValue(forKey: id)
    appSettings.hotkeys.removeValue(forKey: id)
    appSettings.modeOrder.removeAll { $0 == id }
    if activeModeID == id {
      activeWorkflow?.reset()
      activeWorkflow = nil
      activeModeID = nil
      menuBarStatus = .idle
      page = .main
    }
  }

  func moveMode(id: ModeConfig.ID, offset: Int) {
    guard modeConfig(for: id) != nil, offset != 0 else { return }
    ensureModeOrderContainsKnownModes()
    appSettings.modeOrder = Self.reorderedModeIDs(appSettings.modeOrder, moving: id, offset: offset)
  }

  func canDeleteMode(id: ModeConfig.ID) -> Bool {
    guard let existing = modeConfig(for: id) else { return false }
    return existing.id != existing.slot.rawValue
  }

  func canMoveMode(id: ModeConfig.ID, offset: Int) -> Bool {
    guard appSettings.modeOrder.contains(id) else { return false }
    let reordered = Self.reorderedModeIDs(appSettings.modeOrder, moving: id, offset: offset)
    return reordered != appSettings.modeOrder
  }

  private func insertModeID(_ newID: ModeConfig.ID, after existingID: ModeConfig.ID) {
    appSettings.modeOrder.removeAll { $0 == newID }
    if let index = appSettings.modeOrder.firstIndex(of: existingID) {
      appSettings.modeOrder.insert(newID, at: appSettings.modeOrder.index(after: index))
    } else {
      appSettings.modeOrder.append(newID)
    }
  }

  private func ensureModeOrderContainsKnownModes() {
    let knownIDs = Set(appSettings.modes.keys)
    appSettings.modeOrder.removeAll { !knownIDs.contains($0) }
    for config in orderedModeConfigs where !appSettings.modeOrder.contains(config.id) {
      appSettings.modeOrder.append(config.id)
    }
  }

  /// Effective rewrite backend: the global offline switch forces on-device.
  func resolvedRewriteBackend(for type: WorkflowType) -> RewriteBackend {
    resolvedRewriteBackend(for: modeConfig(for: type))
  }

  func resolvedRewriteBackend(for config: ModeConfig) -> RewriteBackend {
    appSettings.secureLocalModeEnabled ? .local : config.rewrite.rewriteBackend
  }

  /// Transcription backend for the rewrite modes — local in secure offline mode so audio never
  /// leaves the device, otherwise OpenAI Whisper. Mirrors the plain transcription mode.
  var rewriteTranscriptionBackend: TranscriptionBackend {
    appSettings.secureLocalModeEnabled ? .local : .remote
  }

  func rewriteProvider(for type: WorkflowType) -> any RewriteProvider {
    rewriteProvider(for: modeConfig(for: type))
  }

  func rewriteProvider(for config: ModeConfig) -> any RewriteProvider {
    switch resolvedRewriteBackend(for: config) {
    case .local:
      // llama.cpp is the only local runtime — every on-device rewrite goes through it.
      return LlamaCppRewriteProvider(modelID: appSettings.selectedLocalLLM.modelID)
    case .openai:
      return OpenAIRewriteProvider(modelID: config.rewrite.modelID)
    }
  }

  func rewriteBackendReady(for type: WorkflowType) -> Bool {
    rewriteBackendReady(for: modeConfig(for: type))
  }

  func rewriteBackendReady(for config: ModeConfig) -> Bool {
    switch resolvedRewriteBackend(for: config) {
    case .local:
      return appSettings.selectedLocalLLM.isConfigured
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
    await rerunRewrite(
      rawTranscript: rawTranscript, as: mode.rawValue, archiveResult: archiveResult)
  }

  func rerunRewrite(
    rawTranscript: String,
    as modeID: ModeConfig.ID,
    archiveResult: Bool = true
  ) async -> Result<String, Error> {
    // Fresh re-run: drop any stale model-fallback note before this run can set one (B6).
    lastRewriteFallbackNote = nil
    let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .failure(RerunError.emptyTranscript) }
    guard let config = modeConfig(for: modeID), config.slot.isRewriteCapable else {
      return .failure(RerunError.notRewriteCapable)
    }
    // Same pre-flight gate as recording: route the user to settings instead of losing the run.
    guard rewriteBackendReady(for: config) else {
      return .failure(RerunError.backendNotReady(resolvedRewriteBackend(for: config)))
    }

    let systemPrompt = RewriteReuse.systemPrompt(
      kind: config.kind,
      rewrite: config.rewrite,
      customTerms: effectiveRewriteTerms,
      memory: memoryContext(for: config),
      userIdentity: userIdentityContext
    )

    do {
      let outcome = try await rewriteProvider(for: config).rewrite(
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
            mode: config.slot,
            modeID: config.id,
            modeName: displayName(for: config),
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
          + "„Lokales Sprachmodell“ ein GGUF-Modell aus."
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

    if appSettings.modeOrder.isEmpty {
      appSettings.modeOrder = WorkflowType.allCases.map(\.rawValue)
    } else {
      for slot in WorkflowType.allCases where !appSettings.modeOrder.contains(slot.rawValue) {
        appSettings.modeOrder.append(slot.rawValue)
      }
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
    let targetVersion = 4
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

    if appSettings.modesSchemaVersion < 4 {
      normalizeDefaultModeFeatureToggles()
    }

    appSettings.modesSchemaVersion = targetVersion
    saveSettings()
  }

  private func normalizeDefaultModeFeatureToggles() {
    for key in Array(appSettings.modes.keys) {
      guard var config = appSettings.modes[key] else { continue }
      switch config.slot {
      case .textImprover:
        config.rewrite.useAutomaticFieldContext = true
        config.rewrite.useMemoryContext = true
        config.rewrite.useSemanticEmailMemory = true
      case .dampfAblassen:
        config.rewrite.useAutomaticFieldContext = true
        config.rewrite.useMemoryContext = true
      case .transcription, .localTranscription, .emojiText:
        break
      }
      appSettings.modes[key] = config
    }
  }

  // MARK: - Custom Display Names

  func displayName(for type: WorkflowType) -> String {
    displayName(for: modeConfig(for: type))
  }

  func displayName(for config: ModeConfig) -> String {
    let name = config.userName.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? ModeConfig.defaultUserName(for: config.slot) : name
  }

  /// Subtitle for a local-rewrite mode: always llama.cpp, with the active model's display name.
  private func localRewriteSubtitle() -> String {
    let selection = appSettings.selectedLocalLLM
    guard selection.isConfigured else {
      return "lokal über llama.cpp — noch kein modell gewählt"
    }
    let name =
      localModelManager.installedLlamaCppModel(for: selection.modelID)?.displayName
      ?? LlamaCppModelCatalog.model(for: selection.modelID)?.displayName
      ?? selection.modelID
    return "lokal über llama.cpp (\(name))"
  }

  func workflowSubtitle(for config: ModeConfig) -> String {
    let type = config.slot
    if type == .emojiText {
      return "emoji-dichte: \(config.rewrite.emojiDensity.displayName)."
    }
    if type == .textImprover || type == .dampfAblassen {
      switch resolvedRewriteBackend(for: config) {
      case .local:
        return localRewriteSubtitle()
      case .openai:
        return type.subtitle
      }
    }
    return type.subtitle
  }

  func workflowSubtitle(for type: WorkflowType) -> String {
    switch type {
    case .transcription:
      if appSettings.secureLocalModeEnabled {
        let modelName = selectedLocalModelName
        return LocalTranscriptionService.isModelInstalled(modelName)
          ? "lokal: \(LocalTranscriptionModel.displayName(for: modelName))."
          : "lokales WhisperKit-Modell fehlt."
      }
      return "online: Whisper über OpenAI."
    case .localTranscription:
      return "nur lokal. kein server."
    case .textImprover, .dampfAblassen, .emojiText:
      switch resolvedRewriteBackend(for: type) {
      case .local:
        return localRewriteSubtitle()
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
      ? "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) ist geladen"
      : "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) laden"
  }

  // MARK: - Workflow Management

  /// Starts a workflow from a tap inside the popover. Keeps `source: .manual` so the paste target
  /// captured when the popover opened (the app that was frontmost before rede took focus) is
  /// preserved, then dismisses the popover so ONLY the floating pill indicates recording.
  func startWorkflowFromPopover(_ type: WorkflowType) {
    startModeFromPopover(type.rawValue)
  }

  func startModeFromPopover(_ modeID: ModeConfig.ID) {
    guard let config = modeConfig(for: modeID) else {
      page = .settings
      return
    }
    startMode(config.id, source: .manual)
    // Only dismiss when a workflow actually started — an unavailable mode routes to .settings and
    // must keep the popover open there.
    guard let active = activeWorkflow, activeModeID == config.id else { return }
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
    startMode(type.rawValue, source: source)
  }

  func startMode(_ modeID: ModeConfig.ID, source: WorkflowLaunchSource = .manual) {
    guard let config = modeConfig(for: modeID), isWorkflowAvailable(config) else {
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
    activeModeID = config.id
    activePasteTarget = capturePasteTarget(for: source)
    let selection = captureSelectionContext(for: config, source: source)
    let automaticContext = captureAutomaticContext(for: config, source: source)
    logRewriteContextCapture(
      modeID: config.id,
      source: source,
      config: config,
      selection: selection,
      automaticContext: automaticContext
    )

    switch config.slot {
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
        rewrite: config.rewrite,
        provider: rewriteProvider(for: config),
        customTerms: effectiveCustomTerms,
        rewriteTerms: effectiveRewriteTerms,
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
        language: transcriptionSettings.language,
        backend: rewriteTranscriptionBackend,
        localModelName: selectedLocalModelName,
        selection: selection,
        automaticContext: automaticContext,
        memoryContext: memoryContext(for: config),
        userIdentity: userIdentityContext,
        emailMemoryLevel: config.rewrite.semanticEmailEnrichmentLevel,
        emailMemoryLoader: emailMemoryLoader(for: config)
      )
      configureWorkflowHandlers(workflow)
      workflow.onVariants = { [weak self] variants in
        self?.handleWorkflowVariants(variants)
      }
      activeWorkflow = workflow
      workflow.start()

    case .dampfAblassen:
      let workflow = DampfAblassenWorkflow(
        rewrite: config.rewrite,
        provider: rewriteProvider(for: config),
        customTerms: effectiveCustomTerms,
        rewriteTerms: effectiveRewriteTerms,
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
        language: transcriptionSettings.language,
        backend: rewriteTranscriptionBackend,
        localModelName: selectedLocalModelName,
        automaticContext: automaticContext,
        memoryContext: memoryContext(for: config),
        userIdentity: userIdentityContext
      )
      configureWorkflowHandlers(workflow)
      workflow.onVariants = { [weak self] variants in
        self?.handleWorkflowVariants(variants)
      }
      activeWorkflow = workflow
      workflow.start()

    case .emojiText:
      let workflow = EmojiTextWorkflow(
        rewrite: config.rewrite,
        provider: rewriteProvider(for: config),
        customTerms: effectiveCustomTerms,
        rewriteTerms: effectiveRewriteTerms,
        dictionary: appSettings.dictationDictionary,
        fuzzyTerms: effectiveFuzzyTerms,
        language: transcriptionSettings.language,
        backend: rewriteTranscriptionBackend,
        localModelName: selectedLocalModelName
      )
      configureWorkflowHandlers(workflow)
      workflow.onVariants = { [weak self] variants in
        self?.handleWorkflowVariants(variants)
      }
      activeWorkflow = workflow
      workflow.start()
    }

    page = source.presentsWorkflowPage ? .workflow : .main
  }

  func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
    isWorkflowAvailable(modeConfig(for: type))
  }

  func isWorkflowAvailable(_ config: ModeConfig) -> Bool {
    guard config.isEnabled else { return false }
    switch config.slot {
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
      return transcriptionReady && rewriteBackendReady(for: config)
    }
  }

  /// Captures the user's text selection for reply/edit modes, only when that mode opts in.
  /// For `.manual` (popover) starts the live frontmost app is rede itself, so we use the
  /// snapshot taken in `prepareForPopoverPresentation` before activation. Hotkey starts prefer the
  /// captured target PID too, because some apps/focus states can race the system-wide AX focus.
  private func captureSelectionContext(for config: ModeConfig, source: WorkflowLaunchSource)
    -> SelectionContext?
  {
    // Only the E-Mail mode exposes the reply-context control today.
    guard config.slot == .textImprover else { return nil }
    guard config.rewrite.replyContextMode != .off else { return nil }
    switch source {
    case .manual:
      if let target = activePasteTarget {
        return SelectionContextService.capture(
          pid: target.processIdentifier,
          appBundleID: target.bundleIdentifier
        ) ?? pendingPopoverSelection
      }
      return pendingPopoverSelection
    case .hotkeyBackground:
      if let target = activePasteTarget {
        return SelectionContextService.capture(
          pid: target.processIdentifier,
          appBundleID: target.bundleIdentifier
        ) ?? SelectionContextService.capture()
      }
      return SelectionContextService.capture()
    }
  }

  /// Captures the current field text as opt-in rewrite context without requiring a selection.
  /// Manual starts reuse the pre-popover snapshot; background hotkeys capture live because the
  /// target app remains frontmost.
  private func captureAutomaticContext(for config: ModeConfig, source: WorkflowLaunchSource)
    -> AutomaticRewriteContext?
  {
    guard config.slot == .textImprover || config.slot == .dampfAblassen else { return nil }
    guard config.rewrite.useAutomaticFieldContext else { return nil }
    guard let target = activePasteTarget else { return nil }
    if source == .manual {
      return SelectionContextService.captureAutomaticFieldContext(
        pid: target.processIdentifier,
        appBundleID: target.bundleIdentifier,
        appName: target.appName,
        windowTitle: target.windowTitle,
        isSecureField: target.isSecureField
      ) ?? pendingPopoverAutomaticContext
    }
    return SelectionContextService.captureAutomaticFieldContext(
      pid: target.processIdentifier,
      appBundleID: target.bundleIdentifier,
      appName: target.appName,
      windowTitle: target.windowTitle,
      isSecureField: target.isSecureField
    )
      ?? SelectionContextService.captureAutomaticFieldContext(
        appBundleID: target.bundleIdentifier,
        appName: target.appName,
        windowTitle: target.windowTitle,
        isSecureField: target.isSecureField
      )
  }

  private func logRewriteContextCapture(
    modeID: ModeConfig.ID,
    source: WorkflowLaunchSource,
    config: ModeConfig,
    selection: SelectionContext?,
    automaticContext: AutomaticRewriteContext?
  ) {
    let diagnostic = RewriteContextCaptureDiagnostic(
      modeID: modeID,
      launchSource: source,
      config: config,
      selection: selection,
      automaticContext: automaticContext,
      targetAppName: activePasteTarget?.appName,
      targetBundleID: activePasteTarget?.bundleIdentifier,
      targetWindowTitle: activePasteTarget?.windowTitle
    )
    contextCaptureLogger.notice("\(diagnostic.logLine, privacy: .public)")
  }

  func stopCurrentWorkflow() {
    activeWorkflow?.stop()
  }

  func resetCurrentWorkflow() {
    activeWorkflow?.reset()
    activeWorkflow = nil
    activeModeID = nil
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

  /// Download the currently selected Whisper model and switch the app into secure-local mode on
  /// success — the "set up local transcription" entry point used by the Modelle tab and onboarding.
  func installSelectedLocalModel() {
    performLocalModelDownload(
      named: selectedLocalModelName, selectOnSuccess: true, enableSecureOnSuccess: true)
  }

  /// Download a specific Whisper model from the unified model-management surface. Makes it the active
  /// transcription model on success (like the Ollama "Laden & nutzen") but never flips secure-local
  /// mode — that stays an explicit, separate switch.
  func installLocalModel(named modelName: String, selectOnSuccess: Bool = true) {
    performLocalModelDownload(
      named: modelName, selectOnSuccess: selectOnSuccess, enableSecureOnSuccess: false)
  }

  private func performLocalModelDownload(
    named modelName: String, selectOnSuccess: Bool, enableSecureOnSuccess: Bool
  ) {
    guard !isDownloadingLocalModel else { return }

    let normalizedName = LocalTranscriptionService.normalizedModelName(modelName)
    localModelDownloadProgress = 0
    localModelDownloadStatusText = "download startet …"
    localModelDownloadErrorText = nil

    Task {
      do {
        let installedURL = try await LocalTranscriptionService.shared.downloadAndInstall(
          modelName: normalizedName
        ) { [weak self] progress in
          Task { @MainActor [weak self] in
            guard let self else { return }
            let clampedProgress = min(max(progress, 0), 1)
            self.localModelDownloadProgress = clampedProgress
            self.localModelDownloadStatusText = "download \(Int(clampedProgress * 100)) %"
          }
        }

        if selectOnSuccess {
          appSettings.selectedLocalTranscriptionModelName = installedURL.lastPathComponent
        }
        if enableSecureOnSuccess {
          appSettings.secureLocalModeEnabled = true
        }
        localModelDownloadProgress = nil
        localModelDownloadStatusText =
          "\(LocalTranscriptionModel.displayName(for: normalizedName)) ist geladen."
        localModelDownloadErrorText = nil

        try? await LocalTranscriptionService.shared.prepare(modelName: normalizedName)
      } catch {
        localModelDownloadProgress = nil
        localModelDownloadStatusText = nil
        localModelDownloadErrorText = error.localizedDescription
      }
    }
  }

  /// Delete an installed Whisper model and re-point the selection so the picker never shows a removed
  /// model as active. Refuses while a download runs to avoid racing the same directory.
  func deleteLocalTranscriptionModel(_ modelName: String) {
    guard !isDownloadingLocalModel else { return }
    let normalizedName = LocalTranscriptionService.normalizedModelName(modelName)
    localModelDownloadErrorText = nil
    Task {
      do {
        try await LocalTranscriptionService.shared.deleteModel(normalizedName)
        let remaining = LocalTranscriptionService.installedModels().map(\.id)
        appSettings.selectedLocalTranscriptionModelName =
          LocalTranscriptionService.selectionAfterDeleting(
            deletedModelName: normalizedName,
            currentSelection: appSettings.selectedLocalTranscriptionModelName,
            remainingInstalledIDs: remaining
          )
      } catch {
        localModelDownloadErrorText = error.localizedDescription
      }
    }
  }

  /// Re-download a Whisper model: remove the on-disk copy, then fetch a fresh one. Keeps it the
  /// active selection when it already was, so "Neu laden" never silently switches the active model.
  func reinstallLocalTranscriptionModel(_ modelName: String) {
    guard !isDownloadingLocalModel else { return }
    let normalizedName = LocalTranscriptionService.normalizedModelName(modelName)
    let wasSelected = selectedLocalModelName == normalizedName
    Task {
      do {
        try await LocalTranscriptionService.shared.deleteModel(normalizedName)
      } catch {
        localModelDownloadErrorText = error.localizedDescription
        return
      }
      installLocalModel(named: normalizedName, selectOnSuccess: wasSelected)
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
    // rede right after this). Only when any E-Mail mode wants reply/edit context.
    pendingPopoverSelection =
      orderedModeConfigs.contains {
        $0.slot == .textImprover && $0.rewrite.replyContextMode != .off
      }
      ? SelectionContextService.capture()
      : nil
    pendingPopoverAutomaticContext = capturePopoverAutomaticContext()
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
  /// to surface the "remove + re-add the rede entry" guidance.
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
    guard appSettings.secureLocalModeEnabled else { return }
    prepareLocalModel(resolvedLocalModelName)
  }

  /// Load + prewarm a local Whisper model off the main actor while `localModelPreparing` is true, so
  /// the UI can show "Modell wird vorbereitet …". Large models take minutes on their first load;
  /// doing this when the model is chosen (not at dictation time) keeps the first dictation from
  /// blocking on a multi-minute ANE compilation. No-op when the model is not installed.
  func prepareLocalModel(_ modelName: String) {
    let normalizedName = LocalTranscriptionService.normalizedModelName(modelName)
    guard LocalTranscriptionService.isModelInstalled(normalizedName) else {
      localModelPreparing = false
      return
    }
    localModelPrewarmTask?.cancel()
    localModelPreparing = true
    localModelPrewarmTask = Task { [weak self] in
      try? await LocalTranscriptionService.shared.prepare(modelName: normalizedName)
      guard !Task.isCancelled else { return }
      self?.localModelPreparing = false
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
    let enrichedRecord = enrichedArchiveRecord(record)
    archiveStore.append(enrichedRecord)
    logPasteContext(for: enrichedRecord)
    if appSettings.memoryContextEnabled {
      memoryCoordinator.ingest(
        rawTranscript: enrichedRecord.rawTranscript, date: enrichedRecord.date)
    }
    ingestEmailSemanticMemoryIfNeeded(enrichedRecord)
  }

  private func ingestEmailSemanticMemoryIfNeeded(_ record: ArchiveRunRecord) {
    guard appSettings.archiveEnabled else { return }
    guard appSettings.semanticEmailMemoryEnabled else { return }
    guard record.mode == .textImprover else { return }
    let modeID = record.modeID ?? activeModeID ?? record.mode.rawValue
    let target = activePasteTarget
    let modelID = appSettings.selectedEmbeddingModelName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelID.isEmpty else { return }

    Task { [weak self] in
      let provider = LlamaCppEmbeddingProvider(modelID: modelID)
      guard let embedding = try? await provider.embed(record.finalText) else { return }
      let memoryRecord = EmailSemanticMemoryRecord(
        date: record.date,
        modeID: modeID,
        appBundleID: target?.bundleIdentifier,
        appName: target?.appName,
        windowTitle: target?.windowTitle,
        rawTranscript: record.rawTranscript,
        finalText: record.finalText,
        embedding: embedding,
        embeddingModel: modelID
      )
      await MainActor.run {
        self?.emailSemanticMemoryStore.append(memoryRecord)
      }
    }
  }

  private func enrichedArchiveRecord(_ record: ArchiveRunRecord) -> ArchiveRunRecord {
    let id = record.modeID ?? activeModeID ?? record.mode.rawValue
    let name =
      record.modeName
      ?? modeConfig(for: id).map { displayName(for: $0) }
      ?? displayName(for: record.mode)
    return record.withModeMetadata(id: id, name: name)
  }

  private func handleWorkflowVariants(_ variants: PendingRewriteVariants) {
    pendingVariantChoice = variants
    onVariantChoice?(variants)
  }

  func chooseVariant(_ variantID: RewriteVariant.ID) {
    guard
      let pending = pendingVariantChoice,
      let variant = pending.variants.first(where: { $0.id == variantID })
    else {
      return
    }
    pendingVariantChoice = nil
    let record = ArchiveRunRecord(
      mode: pending.mode,
      rawTranscript: pending.rawTranscript,
      finalText: variant.text,
      backend: pending.backend,
      durationSec: pending.durationSec,
      date: pending.date
    )
    if appSettings.archiveEnabled {
      handleWorkflowRun(record)
    }
    handleWorkflowOutput(variant.text)
  }

  func copyVariant(_ variantID: RewriteVariant.ID) {
    guard
      let pending = pendingVariantChoice,
      let variant = pending.variants.first(where: { $0.id == variantID })
    else {
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(variant.text, forType: .string)
    pendingVariantChoice = nil
    scheduleWorkflowCleanup(after: 0.2)
  }

  func dismissVariantChoice() {
    pendingVariantChoice = nil
    resetCurrentWorkflow()
  }

  private func emailMemoryLoader(for config: ModeConfig) -> EmailMemoryMatchLoader? {
    guard appSettings.archiveEnabled else { return nil }
    guard appSettings.semanticEmailMemoryEnabled else { return nil }
    guard config.slot == .textImprover else { return nil }
    guard config.rewrite.useSemanticEmailMemory else { return nil }
    let modelID = appSettings.selectedEmbeddingModelName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelID.isEmpty else { return nil }
    let level = config.rewrite.semanticEmailEnrichmentLevel
    let store = emailSemanticMemoryStore

    return { queryText in
      let provider = LlamaCppEmbeddingProvider(modelID: modelID)
      guard let queryEmbedding = try? await provider.embed(queryText) else { return [] }
      let records = await MainActor.run { store.records }
      return EmailMemoryRetriever.retrieve(
        queryEmbedding: queryEmbedding,
        records: records,
        limit: level.retrievalLimit,
        minScore: level.minimumScore
      )
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

    case .variantChoice:
      menuBarStatus = .processing(workflow.type)

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

  private func capturePopoverAutomaticContext() -> AutomaticRewriteContext? {
    guard
      orderedModeConfigs.contains(where: {
        ($0.slot == .textImprover || $0.slot == .dampfAblassen)
          && $0.rewrite.useAutomaticFieldContext
      }),
      let target = lastPopoverPasteTarget
    else { return nil }

    return SelectionContextService.captureAutomaticFieldContext(
      pid: target.processIdentifier,
      appBundleID: target.bundleIdentifier,
      appName: target.appName,
      windowTitle: target.windowTitle,
      isSecureField: target.isSecureField
    )
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
    // is still frontmost and BEFORE rede activates. Best-effort; all nil if Accessibility off.
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
  /// Office-Memory metadata, read via AX at target-capture time (before rede activates) so
  /// the actual Cmd+V paste stays latency-free. All nil when Accessibility is off / unavailable.
  let appName: String?
  let windowTitle: String?
  let elementRole: String?
  /// True when the focused element is a secure/password field. Such a run is treated as sensitive:
  /// its text is NOT archived, NOT context-logged and NOT improvement-tracked (R4-FT-secure-guard).
  let isSecureField: Bool
}

/// Staged candidate for the MEM-2 deferred AX re-read: the text rede inserted plus the target
/// it landed in. Built only when improvement detection is opted in; armed on the paste success path.
private struct ImprovementSnapshot {
  let insertedText: String
  let processIdentifier: pid_t
  let bundleIdentifier: String?
  let appName: String?
  let mode: WorkflowType
}
