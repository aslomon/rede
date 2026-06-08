import Foundation
import Observation

/// Drives the "Lokale Modelle" management page: detects the host, queries the running Ollama
/// server for installed models, and runs in-app downloads (pull) and deletes with live progress.
/// All work stays on the main actor; network calls hop off via `async`. Nothing leaves the machine.
@MainActor
@Observable
final class LocalModelManager {
  /// Live download state for one model tag.
  struct PullUIState: Equatable {
    /// 0...1 for the current layer, or nil while the server is doing indeterminate work
    /// (resolving the manifest, verifying digests).
    var fraction: Double?
    /// Human status line ("Lädt … 42 %", "Manifest …", "Prüfe …").
    var statusText: String
  }

  /// Host capabilities (RAM, chip, free disk), refreshed on demand.
  private(set) var system: SystemCapabilities = .current()
  /// Whether the local Ollama server answered on the last refresh.
  private(set) var serverReachable = false
  /// Whether the Ollama app is installed (so we can offer to launch it when the server is down).
  private(set) var ollamaAppInstalled = false
  /// Installed Ollama app URL, whether system-wide or in the user's Applications folder.
  private(set) var ollamaAppURL: URL?
  /// Models actually pulled into Ollama, with real on-disk sizes (largest first).
  private(set) var installed: [OllamaService.InstalledModel] = []
  /// GGUF models installed for the bundled llama.cpp runtime.
  private(set) var llamaCppInstalled: [LlamaCppModelCatalog.Model] = []
  /// In-flight downloads keyed by tag.
  private(set) var pulls: [String: PullUIState] = [:]
  /// In-flight GGUF downloads keyed by llama.cpp catalog id.
  private(set) var llamaCppDownloads: [String: PullUIState] = [:]
  /// In-flight Ollama app install/start state.
  private(set) var ollamaInstallState: PullUIState?
  /// Last error to surface (download/delete failure), cleared on the next successful action.
  private(set) var lastError: String?
  /// True while the initial/refresh query is running.
  private(set) var isRefreshing = false

  /// Live `Task`s for each running pull, so they can be cancelled. Not observed.
  @ObservationIgnored private var pullTasks: [String: Task<Void, Never>] = [:]
  /// Live GGUF download tasks keyed by catalog id. Not observed.
  @ObservationIgnored private var llamaCppDownloadTasks: [String: Task<Void, Never>] = [:]
  /// Identity token per running pull. A cancel→restart for the same tag mints a new token so a
  /// late-unwinding old Task can't wipe the new pull's bookkeeping. Not observed.
  @ObservationIgnored private var pullTokens: [String: UUID] = [:]
  /// In-flight Ollama app install/start task.
  @ObservationIgnored private var ollamaInstallTask: Task<Void, Never>?
  /// Tags with an in-flight delete, to de-dupe double taps on "Entfernen". Not observed.
  @ObservationIgnored private var deletingTags: Set<String> = []
  @ObservationIgnored private let llamaCppStore = LlamaCppModelStore.default

  // MARK: - Refresh

  /// Re-detect hardware and re-query the Ollama server. Re-entrancy-guarded: several
  /// `LocalLLMModelPicker` instances (one per local-mode card) each call this on appear, so the
  /// guard collapses the thundering herd into a single in-flight query and avoids state flicker.
  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    system = .current()
    ollamaAppURL = OllamaInstallerService.installedAppURL()
    ollamaAppInstalled = ollamaAppURL != nil
    serverReachable = await OllamaService.statusCheck()
    installed = serverReachable ? await OllamaService.installedModelsDetailed() : []
    llamaCppInstalled = llamaCppStore.installedModels()
  }

  // MARK: - Queries

  /// The recommended catalog model for this machine.
  var recommended: OllamaModelCatalog.Model? {
    system.recommendedModel()
  }

  /// Whether `tag` is currently pulled (handles the bare-name → ":latest" convention).
  func isInstalled(_ tag: String) -> Bool {
    OllamaService.isInstalled(tag, in: installed.map(\.name))
  }

  /// The installed record for a catalog tag, if pulled (for showing the real on-disk size).
  /// Reuses `OllamaService.isInstalled`'s normalization so it never diverges from `isInstalled`.
  func installedRecord(for tag: String) -> OllamaService.InstalledModel? {
    installed.first { OllamaService.isInstalled(tag, in: [$0.name]) }
  }

  /// Whether a download is currently running for `tag`.
  func isPulling(_ tag: String) -> Bool {
    pulls[tag] != nil
  }

  func isLlamaCppInstalled(_ modelID: String) -> Bool {
    llamaCppInstalled.contains { $0.id == modelID }
  }

  func isDownloadingLlamaCpp(_ modelID: String) -> Bool {
    llamaCppDownloads[modelID] != nil
  }

  func installedLlamaCppModel(for modelID: String) -> LlamaCppModelCatalog.Model? {
    llamaCppInstalled.first { $0.id == modelID }
  }

  /// Whether the Ollama app is currently being installed or started.
  var isPreparingOllama: Bool {
    ollamaInstallState != nil
  }

  // MARK: - Pull

  /// Start an in-app download of `tag`. No-op if it is already downloading.
  func pull(_ tag: String) {
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, pullTasks[trimmed] == nil else { return }

    lastError = nil
    let token = UUID()
    pullTokens[trimmed] = token
    pulls[trimmed] = PullUIState(fraction: nil, statusText: "Wird vorbereitet …")

    let task = Task { [weak self] in
      do {
        try await OllamaService.pull(trimmed) { progress in
          Task { @MainActor [weak self] in
            self?.applyProgress(progress, for: trimmed, token: token)
          }
        }
        await self?.finishPull(trimmed, token: token, error: nil)
      } catch is CancellationError {
        await self?.finishPull(trimmed, token: token, error: nil)
      } catch {
        await self?.finishPull(trimmed, token: token, error: error.localizedDescription)
      }
    }
    pullTasks[trimmed] = task
  }

  /// Ensure Ollama exists and answers locally, then download `tag`.
  func prepareOllamaAndPull(_ tag: String) {
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if serverReachable {
      pull(trimmed)
      return
    }
    prepareOllama { [weak self] in
      self?.pull(trimmed)
    }
  }

  /// Install or start Ollama, then refresh the visible model state.
  func prepareOllama(onReady: (@MainActor () -> Void)? = nil) {
    guard ollamaInstallTask == nil else { return }
    lastError = nil
    ollamaInstallState = PullUIState(
      fraction: nil,
      statusText: ollamaAppInstalled ? "Ollama wird gestartet …" : "Ollama wird installiert …"
    )

    let task = Task { [weak self] in
      do {
        if await self?.ollamaAppURL != nil {
          _ = try await OllamaInstallerService.startInstalledApp()
        } else {
          _ = try await OllamaInstallerService.installAndStart { progress in
            Task { @MainActor [weak self] in
              self?.ollamaInstallState = PullUIState(
                fraction: nil,
                statusText: progress.statusText
              )
            }
          }
        }
        await self?.finishOllamaPreparation(error: nil, onReady: onReady)
      } catch {
        await self?.finishOllamaPreparation(error: error.localizedDescription, onReady: nil)
      }
    }
    ollamaInstallTask = task
  }

  /// Cancel an in-flight download.
  func cancelPull(_ tag: String) {
    pullTasks[tag]?.cancel()
    pullTasks[tag] = nil
    pullTokens[tag] = nil
    pulls[tag] = nil
  }

  func downloadLlamaCpp(_ model: LlamaCppModelCatalog.Model) {
    guard llamaCppDownloadTasks[model.id] == nil else { return }
    lastError = nil
    llamaCppDownloads[model.id] = PullUIState(
      fraction: nil,
      statusText: "Download wird vorbereitet …"
    )

    let service = LlamaCppDownloadService(store: llamaCppStore)
    let worker = LlamaCppDownloadWorker()
    let task = Task { [weak self] in
      do {
        try await worker.download(model, using: service) { progress in
          Task { @MainActor [weak self] in
            self?.llamaCppDownloads[model.id] = PullUIState(
              fraction: progress.fraction,
              statusText: progress.statusText
            )
          }
        }
        await self?.finishLlamaCppDownload(model.id, error: nil)
      } catch is CancellationError {
        await self?.finishLlamaCppDownload(model.id, error: nil)
      } catch {
        await self?.finishLlamaCppDownload(model.id, error: error.localizedDescription)
      }
    }
    llamaCppDownloadTasks[model.id] = task
  }

  func cancelLlamaCppDownload(_ modelID: String) {
    llamaCppDownloadTasks[modelID]?.cancel()
    llamaCppDownloadTasks[modelID] = nil
    llamaCppDownloads[modelID] = nil
  }

  func deleteLlamaCpp(_ model: LlamaCppModelCatalog.Model) {
    lastError = nil
    do {
      try llamaCppStore.delete(model)
      llamaCppInstalled = llamaCppStore.installedModels()
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func finishLlamaCppDownload(_ modelID: String, error: String?) async {
    llamaCppDownloadTasks[modelID] = nil
    llamaCppDownloads[modelID] = nil
    if let error { lastError = error }
    await refresh()
  }

  private func applyProgress(
    _ progress: OllamaService.PullProgress, for tag: String, token: UUID
  ) {
    guard pullTokens[tag] == token else { return }
    pulls[tag] = PullUIState(
      fraction: progress.fraction,
      statusText: Self.humanStatus(progress)
    )
  }

  private func finishPull(_ tag: String, token: UUID, error: String?) async {
    // Bail if a newer pull (after a cancel→restart) already owns this tag.
    guard pullTokens[tag] == token else { return }
    pullTasks[tag] = nil
    pullTokens[tag] = nil
    pulls[tag] = nil
    if let error { lastError = error }
    await refresh()
  }

  private func finishOllamaPreparation(
    error: String?,
    onReady: (@MainActor () -> Void)?
  ) async {
    ollamaInstallTask = nil
    ollamaInstallState = nil
    if let error {
      lastError = error
    }
    await refresh()
    if error == nil {
      onReady?()
    }
  }

  /// Map a raw Ollama status line + byte counts to a friendly German status.
  static func humanStatus(_ progress: OllamaService.PullProgress) -> String {
    let status = progress.status.lowercased()
    if status.contains("pulling manifest") { return "Manifest wird geladen …" }
    if status.contains("verifying") { return "Wird geprüft …" }
    if status.contains("writing") || status.contains("success") { return "Wird abgeschlossen …" }
    if let fraction = progress.fraction {
      return "Lädt … \(Int(fraction * 100)) %"
    }
    return "Lädt …"
  }

  // MARK: - Delete

  /// Delete an installed model by tag. De-duped against a double tap on "Entfernen".
  func delete(_ tag: String) {
    guard !deletingTags.contains(tag) else { return }
    deletingTags.insert(tag)
    lastError = nil
    Task { [weak self] in
      do {
        try await OllamaService.delete(tag)
      } catch {
        self?.lastError = error.localizedDescription
      }
      self?.deletingTags.remove(tag)
      await self?.refresh()
    }
  }
}
