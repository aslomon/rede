import Foundation

struct RemoteRequestBlocked: LocalizedError, Equatable, Sendable {
    var errorDescription: String? { "Online-Verarbeitung ist im sicheren lokalen Modus gesperrt." }
}

enum DecisionChoiceValue: Codable, Hashable, Sendable {
    case string(String)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }
}

struct DecisionChoiceOption: Encodable, Equatable, Sendable {
    let value: DecisionChoiceValue
    var description: String?

    init(value: DecisionChoiceValue, description: String? = nil) {
        self.value = value
        self.description = description
    }
}

struct DecisionChoiceQuestion: Encodable, Equatable, Sendable {
    let name: String
    let instructions: String
    let choices: [DecisionChoiceOption]
    private let type = "choice"
}

struct DecisionChoiceProbability: Decodable, Equatable, Sendable {
    let value: DecisionChoiceValue
    let probability: Double
}

struct DecisionChoiceAnswer: Equatable, Sendable {
    let choice: DecisionChoiceValue
    let confidence: Double
    let probabilities: [DecisionChoiceProbability]
}

enum DecisionChoiceResult: Equatable, Sendable {
    case choice(DecisionChoiceAnswer)
    case refusal
}

enum DecisionsClientError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case notConfigured
    case invalidResponse
    case unauthorized
    case rateLimited
    case serviceUnavailable
    case httpStatus(Int)
    case networkUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Die Entscheidungsanfrage ist ungültig."
        case .notConfigured: return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .invalidResponse: return "OpenAI hat keine gültige Entscheidung geliefert."
        case .unauthorized: return "OpenAI-Zugriff nicht erlaubt. Bitte API Key und Berechtigungen prüfen."
        case .rateLimited: return "OpenAI ist gerade ausgelastet. Bitte später erneut versuchen."
        case .serviceUnavailable: return "Der OpenAI-Dienst ist gerade nicht verfügbar."
        case .httpStatus(let status): return "OpenAI-Anfrage fehlgeschlagen (Status \(status))."
        case .networkUnavailable: return "Die Verbindung zu OpenAI ist fehlgeschlagen."
        case .timedOut: return "Die OpenAI-Entscheidung hat zu lange gedauert."
        }
    }
}
