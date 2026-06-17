import Foundation
import OSLog
import WhisperKit

private let localTranscriptionLogger = Logger(
  subsystem: "app.rede.mac", category: "LocalTranscription")

private func localTranscriptionMilliseconds(since start: Date, until end: Date = Date()) -> Int {
  Int((end.timeIntervalSince(start) * 1000).rounded())
}

struct LocalTranscriptionModel: Identifiable, Hashable {
  let id: String
  let url: URL
  let isInstalled: Bool

  init(id: String, url: URL, isInstalled: Bool = true) {
    self.id = id
    self.url = url
    self.isInstalled = isInstalled
  }

  var displayName: String {
    Self.displayName(for: id)
  }

  /// Approximate on-disk download size, parsed from the model name suffix (e.g. `_216MB`).
  /// `nil` when the name carries no size hint. Used to set honest "Nicht geladen — N MB" copy.
  var sizeLabel: String? {
    Self.sizeLabel(for: id)
  }

  /// Honest, picker-ready state label. Installed models read "geladen"; missing models
  /// read "nicht geladen — N MB" (or just "nicht geladen" when no size hint is available).
  var installStateLabel: String {
    if isInstalled { return "geladen" }
    if let sizeLabel { return "nicht geladen — \(sizeLabel)" }
    return "nicht geladen"
  }

  /// Parses the trailing `…_<n>MB` size token from a WhisperKit model name into "216 MB".
  static func sizeLabel(for modelName: String) -> String? {
    guard
      let match = modelName.range(
        of: #"(\d+)MB$"#,
        options: .regularExpression
      )
    else {
      return nil
    }
    let digits = modelName[match].dropLast(2)  // strip "MB"
    return "\(digits) MB"
  }

  var shortDisplayName: String {
    if id.contains("small") {
      return "Whisper Small"
    }
    if id.contains("base") {
      return "Whisper Base"
    }
    if id.contains("tiny") {
      return "Whisper Tiny"
    }
    if id.contains("turbo") {
      return "Whisper Turbo"
    }
    if id.contains("large-v3") {
      return "Whisper Large"
    }
    return displayName
  }

  static func displayName(for modelName: String) -> String {
    if modelName.contains("small") {
      return "Whisper Small"
    }
    if modelName.contains("base") {
      return "Whisper Base"
    }
    if modelName.contains("tiny") {
      return "Whisper Tiny"
    }
    if modelName.contains("turbo") {
      return "Whisper Large v3 Turbo"
    }
    if modelName.contains("large-v3") {
      return "Whisper Large v3"
    }
    return
      modelName
      .replacingOccurrences(of: "openai_", with: "")
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
  }
}

enum LocalTranscriptionError: LocalizedError {
  case modelMissing(URL)
  case downloadedModelInvalid(String)
  case noText

  var errorDescription: String? {
    switch self {
    case .modelMissing(let url):
      return "Lokales Modell fehlt: \(url.path)"
    case .downloadedModelInvalid(let modelName):
      return "Das geladene Modell ist unvollständig: \(modelName)"
    case .noText:
      return "Das lokale Modell hat keinen Text erkannt."
    }
  }
}

actor LocalTranscriptionService {
  static let shared = LocalTranscriptionService()

  static let defaultModelName = "openai_whisper-large-v3-v20240930_626MB"
  static let fastModelName = "openai_whisper-large-v3-v20240930_turbo_632MB"
  static let recommendedFastModelName = "openai_whisper-small_216MB"
  static let modelRepo = "argmaxinc/whisperkit-coreml"
  static let whisperKitPrewarmEnabled = false
  static let whisperKitLoadEnabled = true
  static let supportedModelNames = [
    recommendedFastModelName,
    fastModelName,
    defaultModelName,
  ]
  static let modelPageURL = URL(
    string:
      "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB"
  )!
  static let fastModelPageURL = URL(
    string:
      "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo_632MB"
  )!
  static let recommendedFastModelPageURL = URL(
    string:
      "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small_216MB"
  )!

  static func modelPageURL(for modelName: String) -> URL {
    switch normalizedModelName(modelName) {
    case recommendedFastModelName:
      return recommendedFastModelPageURL
    case fastModelName:
      return fastModelPageURL
    case defaultModelName:
      return modelPageURL
    default:
      return URL(
        string: "https://huggingface.co/\(modelRepo)/tree/main/\(normalizedModelName(modelName))")!
    }
  }

  private var whisperKit: WhisperKit?
  private var loadedModelName: String?

  static var isModelInstalled: Bool {
    isModelInstalled(defaultModelName)
  }

  static func modelURL(named modelName: String) -> URL {
    AppSupportPaths.whisperKitModelsDirectoryURL.appendingPathComponent(
      normalizedModelName(modelName), isDirectory: true)
  }

  static func isModelInstalled(_ modelName: String) -> Bool {
    isUsableModel(at: modelURL(named: modelName))
  }

  static func normalizedModelName(_ modelName: String) -> String {
    let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? recommendedFastModelName : trimmed
  }

  static func installedModels() -> [LocalTranscriptionModel] {
    let directory = AppSupportPaths.whisperKitModelsDirectoryURL
    let urls =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    return
      urls
      .filter { isUsableModel(at: $0) }
      .map { LocalTranscriptionModel(id: $0.lastPathComponent, url: $0) }
      .sorted { lhs, rhs in
        if lhs.id == recommendedFastModelName { return true }
        if rhs.id == recommendedFastModelName { return false }
        if lhs.id == fastModelName { return true }
        if rhs.id == fastModelName { return false }
        if lhs.id == defaultModelName { return true }
        if rhs.id == defaultModelName { return false }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
  }

  static func modelOptions() -> [LocalTranscriptionModel] {
    var seen = Set<String>()
    let installed = installedModels()
    let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
    let orderedIDs = supportedModelNames + installed.map(\.id)

    return orderedIDs.compactMap { modelName in
      let normalizedName = normalizedModelName(modelName)
      guard seen.insert(normalizedName).inserted else { return nil }

      if let installedModel = installedByID[normalizedName] {
        return installedModel
      }

      return LocalTranscriptionModel(
        id: normalizedName,
        url: modelURL(named: normalizedName),
        isInstalled: false
      )
    }
  }

  static func resolvedModelName(_ preferredModelName: String) -> String {
    let normalizedName = normalizedModelName(preferredModelName)
    if isModelInstalled(normalizedName) {
      return normalizedName
    }

    return installedModels().first?.id ?? normalizedName
  }

  static func shouldAutoSelectRecommendedFastModel(currentModelName: String) -> Bool {
    guard isModelInstalled(recommendedFastModelName) else {
      return false
    }

    return currentModelName == defaultModelName || currentModelName == fastModelName
  }

  /// After deleting `deletedModelName`, decide which model the picker should select next. Keeps the
  /// current selection when it still exists on disk; otherwise prefers the recommended fast model if
  /// still installed, then any remaining installed model, then the recommended name as a last
  /// resort — so the selection never points at a model that was just removed. Pure for testing.
  static func selectionAfterDeleting(
    deletedModelName: String,
    currentSelection: String,
    remainingInstalledIDs: [String]
  ) -> String {
    let deleted = normalizedModelName(deletedModelName)
    let selection = normalizedModelName(currentSelection)
    if selection != deleted, remainingInstalledIDs.contains(selection) {
      return selection
    }
    if remainingInstalledIDs.contains(recommendedFastModelName) {
      return recommendedFastModelName
    }
    return remainingInstalledIDs.first ?? recommendedFastModelName
  }

  func prepare(modelName: String) async throws {
    let startedAt = Date()
    _ = try await pipeline(modelName: modelName)
    localTranscriptionLogger.info(
      "stage=prepare_pipeline elapsed_ms=\(localTranscriptionMilliseconds(since: startedAt), privacy: .public)"
    )
  }

  /// Remove an installed Whisper model directory from disk. If that model is currently loaded into
  /// the in-memory pipeline, the pipeline is dropped so the next transcription reloads cleanly.
  /// A no-op on the file system when the model is not present (so "re-download" can delete safely).
  func deleteModel(_ modelName: String) throws {
    let normalizedName = Self.normalizedModelName(modelName)
    let url = Self.modelURL(named: normalizedName)
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    if loadedModelName == normalizedName {
      whisperKit = nil
      loadedModelName = nil
    }
  }

  func downloadAndInstall(
    modelName: String,
    progressHandler: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    let normalizedName = Self.normalizedModelName(modelName)
    let destinationURL = Self.modelURL(named: normalizedName)

    if Self.isUsableModel(at: destinationURL) {
      progressHandler(1)
      return destinationURL
    }

    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: AppSupportPaths.whisperKitModelsDirectoryURL,
      withIntermediateDirectories: true
    )

    let downloadRoot = AppSupportPaths.localModelsDirectoryURL
      .appendingPathComponent("downloads", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: downloadRoot, withIntermediateDirectories: true)

    do {
      let downloadedURL = try await WhisperKit.download(
        variant: normalizedName,
        downloadBase: downloadRoot,
        from: Self.modelRepo
      ) { progress in
        let fraction = progress.fractionCompleted
        progressHandler(fraction.isFinite ? fraction : 0)
      }

      guard Self.isUsableModel(at: downloadedURL) else {
        throw LocalTranscriptionError.downloadedModelInvalid(normalizedName)
      }

      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.moveItem(at: downloadedURL, to: destinationURL)
      try? fileManager.removeItem(at: downloadRoot)

      if loadedModelName == normalizedName {
        whisperKit = nil
        loadedModelName = nil
      }

      progressHandler(1)
      return destinationURL
    } catch {
      try? fileManager.removeItem(at: downloadRoot)
      throw error
    }
  }

  func transcribe(
    audioURL: URL, language: String, modelName: String, customTerms: [String] = []
  ) async throws -> String {
    let resolvedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
    let pipeline = try await pipeline(modelName: modelName)

    // Bias the decoder toward configured Eigennamen (names / foreign terms) via a conditioning
    // prompt, so local transcription gets the same vocabulary hint the remote path already uses.
    var promptTokens: [Int] = []
    if !customTerms.isEmpty, let tokenizer = pipeline.tokenizer {
      let promptText = " " + customTerms.joined(separator: ", ")
      promptTokens = tokenizer.encode(text: promptText)
        .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        .prefix(200)
        .map { $0 }
    }

    // First pass: conditioned on the vocabulary prompt (if any).
    var text = try await runTranscription(
      pipeline, audioPath: audioURL.path, language: resolvedLanguage, promptTokens: promptTokens)

    // Some Whisper variants (notably large-v3) emit NOTHING when conditioned on a long prefill
    // prompt, even though the identical audio transcribes fine without it. A vocabulary hint must
    // never cost the user their transcription — retry once without the prompt before giving up.
    if text.isEmpty, !promptTokens.isEmpty {
      text = try await runTranscription(
        pipeline, audioPath: audioURL.path, language: resolvedLanguage, promptTokens: [])
    }

    guard !text.isEmpty else {
      throw LocalTranscriptionError.noText
    }

    return text
  }

  /// Runs one WhisperKit pass and returns the joined, trimmed transcript. `promptTokens` empty means
  /// no vocabulary conditioning. Factored out so the caller can retry promptless on an empty result.
  private func runTranscription(
    _ pipeline: WhisperKit, audioPath: String, language: String, promptTokens: [Int]
  ) async throws -> String {
    var decodeOptions = DecodingOptions(
      task: .transcribe,
      language: language.isEmpty ? nil : language
    )
    if !promptTokens.isEmpty {
      decodeOptions.usePrefillPrompt = true
      decodeOptions.promptTokens = promptTokens
    }
    let startedAt = Date()
    let results = try await pipeline.transcribe(
      audioPath: audioPath,
      decodeOptions: decodeOptions
    )
    localTranscriptionLogger.info(
      "stage=whisper_decode prompt_tokens=\(promptTokens.count, privacy: .public) elapsed_ms=\(localTranscriptionMilliseconds(since: startedAt), privacy: .public)"
    )
    return
      results
      .map(\.text)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func pipeline(modelName: String) async throws -> WhisperKit {
    let resolvedModelName = Self.resolvedModelName(modelName)
    if let whisperKit, loadedModelName == resolvedModelName {
      return whisperKit
    }

    let url = Self.modelURL(named: resolvedModelName)
    guard Self.isUsableModel(at: url) else {
      throw LocalTranscriptionError.modelMissing(url)
    }

    let startedAt = Date()
    let loaded = try await WhisperKit(
      modelFolder: url.path,
      verbose: false,
      prewarm: Self.whisperKitPrewarmEnabled,
      load: Self.whisperKitLoadEnabled,
      download: false
    )
    localTranscriptionLogger.info(
      "stage=pipeline_load prewarm=\(Self.whisperKitPrewarmEnabled, privacy: .public) load=\(Self.whisperKitLoadEnabled, privacy: .public) elapsed_ms=\(localTranscriptionMilliseconds(since: startedAt), privacy: .public)"
    )
    whisperKit = loaded
    loadedModelName = resolvedModelName
    return loaded
  }

  /// A model counts as truly installed only when its directory carries `config.json` AND all
  /// three required CoreML packages. The `config.json` check is what makes the install-state
  /// label trustworthy: an interrupted download can leave the `.mlmodelc` folders in place while
  /// `config.json` is still missing, and WhisperKit refuses to load such a directory. Requiring
  /// it here means the picker never shows "Installiert" for a model that would fail at load time.
  static func isUsableModel(at url: URL) -> Bool {
    let fileManager = FileManager.default
    let requiredEntries = [
      "config.json",
      "AudioEncoder.mlmodelc",
      "MelSpectrogram.mlmodelc",
      "TextDecoder.mlmodelc",
    ]
    return requiredEntries.allSatisfy { entry in
      fileManager.fileExists(atPath: url.appendingPathComponent(entry).path)
    }
  }
}
