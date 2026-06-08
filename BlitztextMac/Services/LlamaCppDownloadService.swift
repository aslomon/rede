import CryptoKit
import Foundation

struct LlamaCppDownloadService: Sendable {
  enum DownloadError: LocalizedError {
    case httpStatus(Int)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
      switch self {
      case .httpStatus(let code):
        return "Der Modell-Download antwortete mit Status \(code)."
      case .checksumMismatch:
        return "Der Modell-Download konnte nicht verifiziert werden."
      }
    }
  }

  struct Progress: Equatable, Sendable {
    let fraction: Double?
    let statusText: String
  }

  let store: LlamaCppModelStore
  let session: URLSession

  init(
    store: LlamaCppModelStore = .default,
    session: URLSession = .shared
  ) {
    self.store = store
    self.session = session
  }

  func download(
    _ model: LlamaCppModelCatalog.Model,
    onProgress: @escaping @Sendable (Progress) -> Void
  ) async throws {
    try store.ensureRootExists()
    let partialURL = try store.partialURL(for: model)
    let finalURL = try store.finalURL(for: model)
    try? FileManager.default.removeItem(at: partialURL)

    onProgress(Progress(fraction: nil, statusText: "Download wird gestartet …"))
    let (temporaryURL, response) = try await session.download(from: model.downloadURL)
    guard let http = response as? HTTPURLResponse else {
      throw DownloadError.httpStatus(0)
    }
    guard http.statusCode == 200 else {
      throw DownloadError.httpStatus(http.statusCode)
    }

    try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
    onProgress(Progress(fraction: nil, statusText: "Download wird geprüft …"))

    let actual = try Self.sha256Hex(for: partialURL)
    guard actual.caseInsensitiveCompare(model.sha256) == .orderedSame else {
      try? FileManager.default.removeItem(at: partialURL)
      throw DownloadError.checksumMismatch(expected: model.sha256, actual: actual)
    }

    try? FileManager.default.removeItem(at: finalURL)
    try FileManager.default.moveItem(at: partialURL, to: finalURL)
    try store.writeVerifiedManifest(for: model, fileURL: finalURL)
    onProgress(Progress(fraction: 1, statusText: "Modell ist installiert.")
    )
  }

  static func sha256Hex(for fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

actor LlamaCppDownloadWorker {
  func download(
    _ model: LlamaCppModelCatalog.Model,
    using service: LlamaCppDownloadService,
    onProgress: @escaping @Sendable (LlamaCppDownloadService.Progress) -> Void
  ) async throws {
    try await service.download(model, onProgress: onProgress)
  }
}
