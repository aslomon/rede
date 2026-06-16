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

    let totalGB = Double(model.sizeBytes) / 1_000_000_000.0
    onProgress(Progress(fraction: 0, statusText: String(format: "Lädt … 0,0 / %.1f GB", totalGB)))

    // Stream with real progress via a download delegate. `URLSession.download(from:)` reports no
    // progress at all, so a multi-GB download looked frozen ("lädt nicht").
    let (temporaryURL, statusCode) = try await Self.downloadWithProgress(
      url: model.downloadURL,
      expectedBytes: model.sizeBytes
    ) { fraction, received in
      let gb = Double(received) / 1_000_000_000.0
      onProgress(
        Progress(
          fraction: fraction, statusText: String(format: "Lädt … %.1f / %.1f GB", gb, totalGB))
      )
    }
    guard statusCode == 200 else {
      throw DownloadError.httpStatus(statusCode)
    }

    try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
    onProgress(Progress(fraction: nil, statusText: "Download wird geprüft …"))

    let actual = try Self.sha256Hex(for: partialURL)
    // A pinned (catalog) sha256 is enforced; a custom model added by URL has none, so the computed
    // hash is recorded instead of rejecting the download.
    if !model.sha256.isEmpty {
      guard actual.caseInsensitiveCompare(model.sha256) == .orderedSame else {
        try? FileManager.default.removeItem(at: partialURL)
        throw DownloadError.checksumMismatch(expected: model.sha256, actual: actual)
      }
    }

    try? FileManager.default.removeItem(at: finalURL)
    try FileManager.default.moveItem(at: partialURL, to: finalURL)
    try store.writeManifest(
      modelID: model.id,
      fileName: model.fileName,
      sha256: actual,
      fileURL: finalURL,
      displayName: model.displayName,
      parameterSize: model.parameterSize,
      quantization: model.quantization,
      downloadURL: model.downloadURL.absoluteString
    )
    onProgress(
      Progress(fraction: 1, statusText: "Modell ist installiert.")
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

  /// Downloads `url` to a stable temporary file, reporting incremental progress, and returns the
  /// file URL plus the HTTP status code. Uses a `URLSessionDownloadTask` delegate because
  /// `URLSession.download(from:)` reports no progress (a multi-GB download then looks frozen).
  private static func downloadWithProgress(
    url: URL,
    expectedBytes: Int64,
    onProgress: @escaping @Sendable (_ fraction: Double?, _ received: Int64) -> Void
  ) async throws -> (URL, Int) {
    let delegate = ProgressDownloadDelegate(expectedBytes: expectedBytes, onProgress: onProgress)
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    return try await withCheckedThrowingContinuation { continuation in
      delegate.continuation = continuation
      session.downloadTask(with: url).resume()
    }
  }
}

/// `URLSessionDownloadDelegate` that bridges progress + completion into async/await. Delegate
/// callbacks arrive serially on the session's background queue, so the mutable state is safe.
private final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate,
  @unchecked Sendable
{
  private let expectedBytes: Int64
  private let onProgress: @Sendable (Double?, Int64) -> Void
  var continuation: CheckedContinuation<(URL, Int), Error>?
  private var resumed = false
  private var lastReportedBytes: Int64 = 0

  init(expectedBytes: Int64, onProgress: @escaping @Sendable (Double?, Int64) -> Void) {
    self.expectedBytes = expectedBytes
    self.onProgress = onProgress
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    // Throttle to ~8 MB steps so we don't flood the main actor with state updates.
    guard totalBytesWritten - lastReportedBytes >= 8_000_000 || lastReportedBytes == 0 else {
      return
    }
    lastReportedBytes = totalBytesWritten
    let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
    let fraction = total > 0 ? min(1, Double(totalBytesWritten) / Double(total)) : nil
    onProgress(fraction, totalBytesWritten)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // `location` is removed once this method returns — move it to a stable temp file synchronously.
    let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("gguf.download")
    do {
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
      finish(.success((destination, status)))
    } catch {
      finish(.failure(error))
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      finish(.failure(error))
    }
    // Success is delivered by didFinishDownloadingTo; nothing to do here on success.
  }

  private func finish(_ result: Result<(URL, Int), Error>) {
    guard !resumed else { return }
    resumed = true
    continuation?.resume(with: result)
    continuation = nil
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
