import Foundation

struct LiveServerError: Decodable, Sendable {
    let code: String?
    let type: String?
    var eventID: String?
    enum CodingKeys: String, CodingKey { case code, type; case eventID = "event_id" }
}

struct LiveWireEvent: Decodable, Sendable {
    let type: String
    let itemID: String?
    let previousItemID: String?
    let delta: String?
    let transcript: String?
    let contentIndex: Int?
    let error: LiveServerError?
    enum CodingKeys: String, CodingKey {
        case type, delta, transcript, error
        case contentIndex = "content_index"
        case itemID = "item_id", previousItemID = "previous_item_id"
    }
}

enum LiveSessionProtocol {
    static func sessionUpdate(_ configuration: LiveConfiguration) throws -> Data {
        var transcription: [String: Any] = ["model": "gpt-live-transcribe", "delay": configuration.delay.rawValue]
        let language = configuration.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !language.isEmpty && language != "auto" { transcription["languages"] = [language] }
        let keywords = sanitizedKeywords(configuration.keywords)
        if !keywords.isEmpty { transcription["keywords"] = keywords }
        let input: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": 24_000],
            "transcription": transcription, "turn_detection": NSNull()
        ]
        return try JSONSerialization.data(withJSONObject: [
            "type": "session.update", "session": ["type": "transcription", "audio": ["input": input]]
        ])
    }

    static func sanitizedKeywords(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let clean = String(value.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0) && $0 != "<" && $0 != ">"
            }.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !result.contains(clean) { result.append(clean) }
            if result.count == 50 { break }
        }
        return result
    }

    static func append(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "input_audio_buffer.append", "audio": data.base64EncodedString()
        ])
    }
    static func commit(eventID: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "input_audio_buffer.commit", "event_id": eventID])
    }

    static func failure(_ error: Error) -> LiveFailure {
        if let failure = error as? LiveFailure { return failure }
        if let url = error as? URLError, url.code == .timedOut { return .timeout }
        return .network
    }
    static func serverFailure(_ error: LiveServerError?) -> LiveFailure {
        let code = error?.code ?? "unknown"
        if ["invalid_api_key", "authentication_error", "unauthorized"].contains(code) { return .unauthorized }
        if ["model_not_found", "model_not_available"].contains(code) { return .modelUnavailable }
        return .server(code: code)
    }
}
