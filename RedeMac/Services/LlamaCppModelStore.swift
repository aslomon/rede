import Foundation

struct LlamaCppModelStore: Sendable {
  struct VerifiedManifest: Codable, Equatable, Sendable {
    let modelID: String
    let fileName: String
    let sha256: String
    let sizeBytes: Int64
    // Self-describing fields so custom / dynamically-added models survive without the static
    // catalog. Absent in older manifests → decode to nil.
    var displayName: String? = nil
    var parameterSize: String? = nil
    var quantization: String? = nil
    var downloadURL: String? = nil
  }

  enum StoreError: LocalizedError {
    case unsafeFileName(String)
    case outsideModelDirectory(URL)
    case notInstalled(String)

    var errorDescription: String? {
      switch self {
      case .unsafeFileName(let fileName):
        return "Unsicherer Modell-Dateiname: \(fileName)"
      case .outsideModelDirectory:
        return "Der Modellpfad liegt außerhalb des rede-Modellordners."
      case .notInstalled(let id):
        return "Das lokale Modell „\(id)“ ist nicht installiert."
      }
    }
  }

  static let `default` = LlamaCppModelStore(
    rootDirectory: AppSupportPaths.llamaCppModelsDirectoryURL
  )

  let rootDirectory: URL

  func ensureRootExists() throws {
    try FileManager.default.createDirectory(
      at: rootDirectory,
      withIntermediateDirectories: true
    )
  }

  func finalURL(for model: LlamaCppModelCatalog.Model) throws -> URL {
    try safeURL(fileName: model.fileName)
  }

  func partialURL(for model: LlamaCppModelCatalog.Model) throws -> URL {
    try safeURL(fileName: "\(model.fileName).partial")
  }

  func manifestURL(for model: LlamaCppModelCatalog.Model) throws -> URL {
    try safeURL(fileName: "\(model.fileName).manifest.json", allowedSuffixes: [".manifest.json"])
  }

  func isInstalled(_ model: LlamaCppModelCatalog.Model) -> Bool {
    guard let url = try? finalURL(for: model) else { return false }
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else { return false }
    return (try? verifiedManifest(for: model)) != nil
  }

  func installedModels() -> [LlamaCppModelCatalog.Model] {
    LlamaCppModelCatalog.models.filter(isInstalled)
  }

  /// All on-disk manifests whose `.gguf` is present with a matching size — the source of truth for
  /// installed models regardless of whether they are in the static catalog (custom / HF models too).
  func installedManifests() -> [VerifiedManifest] {
    let fileManager = FileManager.default
    guard
      let entries = try? fileManager.contentsOfDirectory(
        at: rootDirectory, includingPropertiesForKeys: nil)
    else { return [] }
    return
      entries
      .filter { $0.lastPathComponent.hasSuffix(".manifest.json") }
      .compactMap { url -> VerifiedManifest? in
        guard let data = try? Data(contentsOf: url),
          let manifest = try? JSONDecoder().decode(VerifiedManifest.self, from: data),
          let fileURL = try? safeURL(fileName: manifest.fileName),
          let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
          (attributes[.size] as? NSNumber)?.int64Value == manifest.sizeBytes
        else { return nil }
        return manifest
      }
  }

  /// The on-disk file URL for an installed model id (catalog or custom), resolved via its manifest.
  func installedFileURL(forID modelID: String) throws -> URL {
    guard let manifest = installedManifests().first(where: { $0.modelID == modelID }) else {
      throw StoreError.notInstalled(modelID)
    }
    return try safeURL(fileName: manifest.fileName)
  }

  /// Writes a manifest for any downloaded model file (catalog or custom), recording the real size.
  func writeManifest(
    modelID: String,
    fileName: String,
    sha256: String,
    fileURL: URL,
    displayName: String? = nil,
    parameterSize: String? = nil,
    quantization: String? = nil,
    downloadURL: String? = nil
  ) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let manifest = VerifiedManifest(
      modelID: modelID, fileName: fileName, sha256: sha256, sizeBytes: size,
      displayName: displayName, parameterSize: parameterSize, quantization: quantization,
      downloadURL: downloadURL)
    let data = try JSONEncoder().encode(manifest)
    try data.write(
      to: try safeURL(fileName: "\(fileName).manifest.json", allowedSuffixes: [".manifest.json"]),
      options: .atomic)
  }

  /// Deletes an installed model (gguf + manifest) by id, via its manifest.
  func deleteByID(_ modelID: String) throws {
    guard let manifest = installedManifests().first(where: { $0.modelID == modelID }) else {
      return
    }
    let fileURL = try safeURL(fileName: manifest.fileName)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
    let manifestURL = try safeURL(
      fileName: "\(manifest.fileName).manifest.json", allowedSuffixes: [".manifest.json"])
    if FileManager.default.fileExists(atPath: manifestURL.path) {
      try FileManager.default.removeItem(at: manifestURL)
    }
  }

  func delete(_ model: LlamaCppModelCatalog.Model) throws {
    let url = try finalURL(for: model)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    let manifest = try manifestURL(for: model)
    if FileManager.default.fileExists(atPath: manifest.path) {
      try FileManager.default.removeItem(at: manifest)
    }
  }

  func writeVerifiedManifest(for model: LlamaCppModelCatalog.Model, fileURL: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let size = attributes[.size] as? NSNumber
    let manifest = VerifiedManifest(
      modelID: model.id,
      fileName: model.fileName,
      sha256: model.sha256,
      sizeBytes: size?.int64Value ?? 0
    )
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: try manifestURL(for: model), options: .atomic)
  }

  func verifiedManifest(for model: LlamaCppModelCatalog.Model) throws -> VerifiedManifest? {
    let manifestURL = try manifestURL(for: model)
    guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(VerifiedManifest.self, from: data)
    guard manifest.modelID == model.id,
      manifest.fileName == model.fileName,
      manifest.sha256.caseInsensitiveCompare(model.sha256) == .orderedSame
    else { return nil }

    let finalURL = try finalURL(for: model)
    let attributes = try FileManager.default.attributesOfItem(atPath: finalURL.path)
    let size = attributes[.size] as? NSNumber
    guard size?.int64Value == manifest.sizeBytes else { return nil }
    return manifest
  }

  func verifyFileChecksum(for model: LlamaCppModelCatalog.Model) throws -> Bool {
    let actual = try LlamaCppDownloadService.sha256Hex(for: try finalURL(for: model))
    return actual.caseInsensitiveCompare(model.sha256) == .orderedSame
  }

  private func safeURL(
    fileName: String,
    allowedSuffixes: [String] = [".gguf", ".gguf.partial"]
  ) throws -> URL {
    let lastComponent = URL(fileURLWithPath: fileName).lastPathComponent
    guard lastComponent == fileName,
      allowedSuffixes.contains(where: { fileName.hasSuffix($0) })
    else {
      throw StoreError.unsafeFileName(fileName)
    }

    let root = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = root.appendingPathComponent(fileName, isDirectory: false)
      .standardizedFileURL
      .resolvingSymlinksInPath()

    guard candidate.path.hasPrefix(root.path + "/") else {
      throw StoreError.outsideModelDirectory(candidate)
    }
    return candidate
  }
}
