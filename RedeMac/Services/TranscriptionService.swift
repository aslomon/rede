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
    let code: String?
    let param: String?
  }

  let error: APIError?
}

private struct TranscriptionOpenAIResponse: Decodable {
  let text: String
}

enum TranscriptionService {
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  private enum Model: String {
    case current = "gpt-transcribe"
    case legacy = "whisper-1"
  }
  private enum CompatibilityError: Error { case fallbackRequired }
  private struct Input {
    let audioURL: URL
    let customTerms: [String]
    let language: String?
    let apiKeyProvider: @Sendable () -> String?
  }

  /// The file transcription upload limit is 25 MB. Beyond this the API rejects the request, so we fail
  /// early with a clear message instead of wasting an upload. Local WhisperKit has no such limit.
  static let remoteUploadByteLimit = 25 * 1024 * 1024
  private static let transcriptionsURL = URL(
    string: "https://api.openai.com/v1/audio/transcriptions")!

  /// Pure check used before the remote upload: true when the audio exceeds the 25 MB cap.
  static func exceedsRemoteUploadLimit(byteCount: Int) -> Bool {
    byteCount > remoteUploadByteLimit
  }

  /// Per-request inactivity timeout (resets while data flows). 120 s is ample headroom for a long
  /// multipart upload to keep streaming without a stall being misread as a timeout.
  static let requestTimeout: TimeInterval = 120
  /// Hard cap on the WHOLE transfer (upload + server-side transcription). This — not the inactivity
  /// timeout — is what previously truncated long dictations at 60 s. 10 min covers a ~25 MB upload on
  /// a slow link plus model processing time, so multi-minute dictations complete online.
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
    language: String? = nil,
    isRemoteAllowed: @escaping @Sendable () -> Bool = { true }
  ) async throws -> String {
    let input = Input(audioURL: audioURL, customTerms: customTerms, language: language,
      apiKeyProvider: { KeychainService.load(key: .openAIAPIKey) })
    return try await transcribe(input: input, isRemoteAllowed: isRemoteAllowed,
      transport: { request in try await session.data(for: request) })
  }

  static func transcribe(
    audioURL: URL,
    customTerms: [String] = [],
    language: String? = nil,
    apiKey: String,
    isRemoteAllowed: @escaping @Sendable () -> Bool = { true },
    transport: @escaping Transport
  ) async throws -> String {
    try await transcribe(audioURL: audioURL, customTerms: customTerms, language: language,
      apiKeyProvider: { apiKey }, isRemoteAllowed: isRemoteAllowed, transport: transport)
  }

  static func transcribe(
    audioURL: URL, customTerms: [String] = [], language: String? = nil,
    apiKeyProvider: @escaping @Sendable () -> String?,
    isRemoteAllowed: @escaping @Sendable () -> Bool = { true }, transport: @escaping Transport
  ) async throws -> String {
    let input = Input(audioURL: audioURL, customTerms: customTerms, language: language,
      apiKeyProvider: apiKeyProvider)
    return try await transcribe(input: input, isRemoteAllowed: isRemoteAllowed, transport: transport)
  }

  private static func transcribe(
    input: Input, isRemoteAllowed: @Sendable () -> Bool, transport: Transport
  ) async throws -> String {
    defer { try? FileManager.default.removeItem(at: input.audioURL) }
    do {
      return try await send(input: input, model: .current,
        isRemoteAllowed: isRemoteAllowed, transport: transport)
    } catch CompatibilityError.fallbackRequired {
      return try await send(input: input, model: .legacy,
        isRemoteAllowed: isRemoteAllowed, transport: transport)
    }
  }

  private static func send(
    input: Input, model: Model, isRemoteAllowed: @Sendable () -> Bool, transport: Transport
  ) async throws -> String {
    try Task.checkCancellation()
    let request = try makeRequest(input: input, model: model, isRemoteAllowed: isRemoteAllowed)
    let (data, response) = try await transport(request)
    try Task.checkCancellation()
    return try decodedTranscript(data: data, response: response, model: model)
  }

  private static func makeRequest(
    input: Input, model: Model, isRemoteAllowed: @Sendable () -> Bool
  ) throws -> URLRequest {
    try Task.checkCancellation()
    guard isRemoteAllowed() else { throw OpenAIRemotePolicyError.remoteNotAllowed }
    try Task.checkCancellation()
    let fileSize = (try? input.audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard !exceedsRemoteUploadLimit(byteCount: fileSize) else {
      throw TranscriptionError.fileTooLarge
    }
    let audioData = try Data(contentsOf: input.audioURL, options: [.mappedIfSafe])
    let boundary = UUID().uuidString
    let body = multipartBody(audioData: audioData, boundary: boundary,
      customTerms: input.customTerms, language: input.language, model: model)
    try Task.checkCancellation()
    guard isRemoteAllowed() else { throw OpenAIRemotePolicyError.remoteNotAllowed }
    try Task.checkCancellation()
    guard let apiKey = input.apiKeyProvider() else { throw TranscriptionError.notConfigured }
    var request = URLRequest(url: transcriptionsURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(model == .current ? "application/json" : "text/plain",
      forHTTPHeaderField: "Accept")
    request.timeoutInterval = requestTimeout
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.httpBody = body
    return request
  }

  private static func multipartBody(
    audioData: Data, boundary: String, customTerms: [String], language: String?, model: Model
  ) -> Data {
    var body = Data()
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
    body.append("Content-Type: audio/m4a\r\n\r\n")
    body.append(audioData)
    body.append("\r\n")
    appendField("model", value: model.rawValue, boundary: boundary, to: &body)
    appendField("response_format", value: model == .current ? "json" : "text",
      boundary: boundary, to: &body)
    appendHints(customTerms: customTerms, language: language, model: model,
      boundary: boundary, to: &body)
    body.append("--\(boundary)--\r\n")
    return body
  }

  private static func appendHints(
    customTerms: [String], language: String?, model: Model, boundary: String, to body: inout Data
  ) {
    if model == .current {
      for term in customTerms.compactMap(validKeyword) {
        appendField("keywords[]", value: term, boundary: boundary, to: &body)
      }
    } else if !customTerms.isEmpty {
      appendField("prompt", value: "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))",
        boundary: boundary, to: &body)
    }
    if let hint = language?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
      appendField(model == .current ? "languages[]" : "language", value: hint,
        boundary: boundary, to: &body)
    }
  }

  private static func validKeyword(_ term: String) -> String? {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    let invalidCharacters = CharacterSet(charactersIn: "<>\r\n")
    guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: invalidCharacters) == nil else {
      return nil
    }
    return trimmed
  }

  private static func appendField(
    _ name: String, value: String, boundary: String, to body: inout Data
  ) {
    body.append("--\(boundary)\r\n")
    body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
    body.append(value)
    body.append("\r\n")
  }

  private static func decodedTranscript(
    data: Data, response: URLResponse, model: Model
  ) throws -> String {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranscriptionError.networkError("Ungueltige Antwort")
    }
    guard httpResponse.statusCode == 200 else {
      let error = (try? JSONDecoder().decode(TranscriptionOpenAIErrorResponse.self, from: data))?.error
      if model == .current, shouldUseLegacy(status: httpResponse.statusCode, error: error) {
        throw CompatibilityError.fallbackRequired
      }
      throw TranscriptionError.apiError(error?.message ?? "Status \(httpResponse.statusCode)")
    }
    let text: String?
    if model == .current {
      text = (try? JSONDecoder().decode(TranscriptionOpenAIResponse.self, from: data))?.text
    } else {
      text = String(data: data, encoding: .utf8)
    }
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TranscriptionError.apiError("Transkription fehlgeschlagen")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func shouldUseLegacy(
    status: Int, error: TranscriptionOpenAIErrorResponse.APIError?
  ) -> Bool {
    if status == 404 { return true }
    if status == 403 { return error?.code == "model_not_found" }
    guard status == 400 else { return false }
    if error?.code == "model_not_found" { return true }
    let message = error?.message?.lowercased() ?? ""
    let parameter = error?.param?.lowercased().replacingOccurrences(of: "[]", with: "")
    let namesModernParameter = ["languages", "keywords"].contains(parameter)
      || message.range(of: #"\b(?:languages|keywords)(?:\[\])?\b"#,
        options: .regularExpression) != nil
    let rejectsParameter = error?.code == "unsupported_parameter"
      || ["unsupported parameter", "unknown parameter", "unrecognized parameter"].contains {
        message.contains($0)
      }
      || message.range(of: #"\bparameter\b.*\b(?:unsupported|not supported)\b"#,
        options: .regularExpression) != nil
    return namesModernParameter && rejectsParameter
  }

}

extension Data {
  fileprivate mutating func append(_ string: String) {
    if let data = string.data(using: .utf8) {
      append(data)
    }
  }
}
