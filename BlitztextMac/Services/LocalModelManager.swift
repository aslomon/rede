import Foundation
import Observation

/// Drives the "Lokale Modelle" management page: detects the host and runs in-app GGUF downloads
/// and deletes for the bundled llama.cpp runtime with live progress. All work stays on the main
/// actor; network calls hop off via `async`. Nothing leaves the machine.
@MainActor
@Observable
final class LocalModelManager {
  /// Live download state for one model.
  struct PullUIState: Equatable {
    /// 0...1 while downloading, or nil during indeterminate work (verifying the checksum).
    var fraction: Double?
    /// Human status line ("Lädt … 1.2 / 1.3 GB", "Download wird geprüft …").
    var statusText: String
  }

  /// Host capabilities (RAM, chip, free disk), refreshed on demand.
  private(set) var system: SystemCapabilities = .current()
  /// GGUF rewrite models installed for the bundled llama.cpp runtime.
  private(set) var llamaCppInstalled: [LlamaCppModelCatalog.Model] = []
  /// GGUF embedding models installed for semantic e-mail memory.
  private(set) var llamaCppEmbeddingInstalled: [LlamaCppModelCatalog.Model] = []
  /// In-flight GGUF downloads keyed by llama.cpp catalog id.
  private(set) var llamaCppDownloads: [String: PullUIState] = [:]
  /// Last error to surface (download/delete failure), cleared on the next successful action.
  private(set) var lastError: String?
  /// True while the initial/refresh query is running.
  private(set) var isRefreshing = false
  /// Chat models fetched live from Hugging Face for the "browse more" section.
  private(set) var huggingFaceModels: [LlamaCppModelCatalog.Model] = []
  private(set) var isFetchingHuggingFace = false
  @ObservationIgnored private var didFetchHuggingFace = false

  /// Live GGUF download tasks keyed by catalog id. Not observed.
  @ObservationIgnored private var llamaCppDownloadTasks: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private let llamaCppStore = LlamaCppModelStore.default

  /// Read the installed GGUF models from disk at creation time, so installed chat/embedding models
  /// are known immediately on launch. Without this, `llamaCppInstalled` stayed empty until a model
  /// view ran `refresh()` on appear — so local rewrite looked unavailable (and the engine wasn't
  /// offered) right after a restart until the user opened the Modelle tab. Disk-only + cheap; the
  /// `system` capabilities keep their `.current()` default and refresh on demand.
  init() {
    reloadInstalledLlamaCpp()
  }

  // MARK: - Refresh

  /// Re-detect hardware and re-read the installed GGUF models from disk. Re-entrancy-guarded:
  /// several `LocalLLMModelPicker` instances each call this on appear, so the guard collapses the
  /// thundering herd into a single in-flight query and avoids state flicker.
  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    system = .current()
    reloadInstalledLlamaCpp()
  }

  // MARK: - Queries

  /// The recommended chat model for this Mac: the best-quality catalog entry that fits RAM + disk.
  var recommended: LlamaCppModelCatalog.Model? {
    system.recommendedModel()
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

  func isLlamaCppEmbeddingInstalled(_ modelID: String) -> Bool {
    llamaCppEmbeddingInstalled.contains { $0.id == modelID }
  }

  /// Reloads both installed-model lists (chat + embedding) from the on-disk manifests, so custom /
  /// dynamically-added models show up alongside catalog ones.
  private func reloadInstalledLlamaCpp() {
    let manifests = llamaCppStore.installedManifests()
    let embeddingIDs = Set(LlamaCppModelCatalog.embeddingModels.map(\.id))
    llamaCppInstalled =
      manifests
      .filter { !embeddingIDs.contains($0.modelID) }
      .map(LlamaCppModelCatalog.installedModel(from:))
      .sorted { $0.qualityRank > $1.qualityRank }
    llamaCppEmbeddingInstalled =
      manifests
      .filter { embeddingIDs.contains($0.modelID) }
      .map(LlamaCppModelCatalog.installedModel(from:))
  }

  /// Adds + downloads a custom GGUF model from a direct URL (no pinned checksum — the hash is
  /// recorded after download).
  func downloadCustomLlamaCpp(urlString: String) {
    guard let model = LlamaCppModelCatalog.customModel(fromURLString: urlString) else {
      lastError = "Ungültige URL. Erwartet wird ein direkter https-Link zu einer .gguf-Datei."
      return
    }
    downloadLlamaCpp(model)
  }

  // MARK: - Download

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
      reloadInstalledLlamaCpp()
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

  // MARK: - Hugging Face catalog (dynamic)

  /// Fetches the live HF catalog once (e.g. when the browse section first appears).
  func fetchHuggingFaceModelsIfNeeded() async {
    guard !didFetchHuggingFace, !isFetchingHuggingFace else { return }
    await fetchHuggingFaceModels()
  }

  func fetchHuggingFaceModels() async {
    guard !isFetchingHuggingFace else { return }
    isFetchingHuggingFace = true
    defer { isFetchingHuggingFace = false }
    let service = HuggingFaceModelService(
      session: URLSession(configuration: .ephemeral))
    huggingFaceModels = await service.fetchChatModels()
    didFetchHuggingFace = true
  }
}
