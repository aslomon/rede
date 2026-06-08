import Foundation

enum TranscriptionError: LocalizedError {
  case noFile
  case notConfigured
  case fileTooLarge
  case networkError(String)
  case apiError(String)

  var errorDescription: String? {
    switch self {
    case .noFile:
      return "Keine Audio-Datei gefunden"
    case .notConfigured:
      return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
    case .fileTooLarge:
      return
        "Aufnahme zu groß für die Online-Transkription (max. 25 MB) — nutze den lokalen Modus oder kürzere Aufnahmen."
    case .networkError(let msg):
      return "Netzwerkfehler: \(msg)"
    case .apiError(let msg):
      return "OpenAI-Fehler: \(msg)"
    }
  }
}

private struct TranscriptionOpenAIErrorResponse: Decodable {
  struct APIError: Decodable {
    let message: String?
  }

  let error: APIError?
}

enum TranscriptionService {
  private static let remoteModel = "whisper-1"
  /// whisper-1's hard upload limit is 25 MB. Beyond this the API rejects the request, so we fail
  /// early with a clear message instead of wasting an upload. Local WhisperKit has no such limit.
  static let remoteUploadByteLimit = 25 * 1024 * 1024
  private static let transcriptionsURL = URL(
    string: "https://api.openai.com/v1/audio/transcriptions")!

  /// Pure check used before the remote upload: true when the audio exceeds whisper-1's 25 MB cap.
  static func exceedsRemoteUploadLimit(byteCount: Int) -> Bool {
    byteCount > remoteUploadByteLimit
  }

  /// Per-request inactivity timeout (resets while data flows). 120 s is ample headroom for a long
  /// multipart upload to keep streaming without a stall being misread as a timeout.
  static let requestTimeout: TimeInterval = 120
  /// Hard cap on the WHOLE transfer (upload + server-side transcription). This — not the inactivity
  /// timeout — is what previously truncated long dictations at 60 s. 10 min covers a ~25 MB upload on
  /// a slow link plus whisper-1's processing time, so multi-minute dictations complete online.
  static let resourceTimeout: TimeInterval = 600

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = resourceTimeout
    return URLSession(configuration: configuration)
  }()

  static func transcribe(
    audioURL: URL,
    customTerms: [String] = [],
    language: String? = nil
  ) async throws -> String {
    guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
      throw TranscriptionError.notConfigured
    }

    return try await Task.detached(priority: .userInitiated) {
      defer {
        try? FileManager.default.removeItem(at: audioURL)
      }

      let boundary = UUID().uuidString
      var request = URLRequest(url: transcriptionsURL)
      request.httpMethod = "POST"
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      request.setValue(
        "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
      request.setValue("text/plain, application/json", forHTTPHeaderField: "Accept")
      request.timeoutInterval = requestTimeout
      request.cachePolicy = .reloadIgnoringLocalCacheData

      // whisper-1 rejects uploads over 25 MB — bail out before reading/sending the audio.
      let fileSize = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      if exceedsRemoteUploadLimit(byteCount: fileSize) {
        throw TranscriptionError.fileTooLarge
      }

      let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])

      var body = Data()
      body.append("--\(boundary)\r\n")
      body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
      body.append("Content-Type: audio/m4a\r\n\r\n")
      body.append(audioData)
      body.append("\r\n")

      body.append("--\(boundary)\r\n")
      body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
      body.append(remoteModel)
      body.append("\r\n")

      body.append("--\(boundary)\r\n")
      body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
      body.append("text")
      body.append("\r\n")

      if !customTerms.isEmpty {
        let prompt = "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))"
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
        body.append(prompt)
        body.append("\r\n")
      }

      if let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.append(language.trimmingCharacters(in: .whitespacesAndNewlines))
        body.append("\r\n")
      }

      body.append("--\(boundary)--\r\n")
      request.httpBody = body

      let (data, response) = try await session.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw TranscriptionError.networkError("Ungueltige Antwort")
      }

      guard httpResponse.statusCode == 200 else {
        throw TranscriptionError.apiError(
          openAIErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
      }

      guard
        let text = String(data: data, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
      else {
        throw TranscriptionError.apiError("Transkription fehlgeschlagen")
      }

      return text
    }.value
  }

  private static func openAIErrorMessage(from data: Data) -> String? {
    (try? JSONDecoder().decode(TranscriptionOpenAIErrorResponse.self, from: data))?.error?.message
  }
}

extension Data {
  fileprivate mutating func append(_ string: String) {
    if let data = string.data(using: .utf8) {
      append(data)
    }
  }
}
