import Foundation

struct DecisionsHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

struct DecisionsClient: Sendable {
    typealias Transport = @Sendable (Data) async throws -> DecisionsHTTPResponse
    static let modelID = "gpt-6-luna"
    static let maximumInputBytes = 10_485_760
    /// JSON schema string lengths count Unicode scalars, not user-perceived grapheme clusters.
    static let maximumQuestionCharacters = 1_048_576
    static let maximumRequestBytes = maximumInputBytes + maximumQuestionCharacters
    static let maximumResponseBytes = 1_048_576

    private let transport: Transport
    private let isRemoteAllowed: @Sendable () -> Bool

    private struct Request: Encodable {
        let model: String
        let input: String
        let questions: [DecisionChoiceQuestion]
    }

    private struct Response: Decodable {
        let answers: [ResponseAnswer]
    }
    private struct ResponseAnswer: Decodable {
        let type: String
        let name: String?
        let choice: DecisionChoiceValue?
        let confidence: Double?
        let probabilities: [DecisionChoiceProbability]?
    }

    init(isRemoteAllowed: @escaping @Sendable () -> Bool = { true }, transport: Transport? = nil) {
        self.isRemoteAllowed = isRemoteAllowed
        self.transport = transport ?? { body in
            try await OpenAIDecisionsTransport(isRemoteAllowed: isRemoteAllowed).send(body)
        }
    }

    init(transport: @escaping Transport) {
        self.init(isRemoteAllowed: { true }, transport: transport)
    }

    func choose(input: String, question: DecisionChoiceQuestion) async throws -> DecisionChoiceResult {
        try Task.checkCancellation()
        guard isRemoteAllowed() else { throw RemoteRequestBlocked() }
        try Self.validate(input: input, question: question)
        let body = try JSONEncoder().encode(Request(model: Self.modelID, input: input, questions: [question]))
        guard body.count <= Self.maximumRequestBytes else { throw DecisionsClientError.invalidRequest }
        let response: DecisionsHTTPResponse
        do {
            guard isRemoteAllowed() else { throw RemoteRequestBlocked() }
            response = try await transport(body)
        } catch {
            try Task.checkCancellation()
            throw Self.transportFailure(error)
        }
        try Task.checkCancellation()
        try Self.checkStatus(response.statusCode)
        return try Self.decode(response.data, question: question)
    }

    private static func transportFailure(_ error: Error) -> Error {
        if error is CancellationError { return CancellationError() }
        if let blocked = error as? RemoteRequestBlocked { return blocked }
        if let known = error as? DecisionsClientError { return known }
        if let url = error as? URLError {
            if url.code == .cancelled { return CancellationError() }
            return url.code == .timedOut ? DecisionsClientError.timedOut : DecisionsClientError.networkUnavailable
        }
        return DecisionsClientError.networkUnavailable
    }

    private static func validate(input: String, question: DecisionChoiceQuestion) throws {
        let values = question.choices.map(\.value)
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.utf8.count <= maximumInputBytes,
              validQuestionText(question.name), validQuestionText(question.instructions),
              (2...255).contains(values.count), Set(values).count == values.count,
              question.choices.allSatisfy(validOption), withinRequestByteBudget(input: input, question: question)
        else { throw DecisionsClientError.invalidRequest }
    }

    private static func validQuestionText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.unicodeScalars.count <= maximumQuestionCharacters
    }

    private static func validOption(_ option: DecisionChoiceOption) -> Bool {
        if case .string(let value) = option.value, !validQuestionText(value) { return false }
        return (option.description?.unicodeScalars.count ?? 0) <= maximumQuestionCharacters
    }

    private static func withinRequestByteBudget(input: String, question: DecisionChoiceQuestion) -> Bool {
        var remaining = maximumRequestBytes - input.utf8.count
        var strings = [question.name, question.instructions]
        for option in question.choices {
            if case .string(let value) = option.value { strings.append(value) }
            if let description = option.description { strings.append(description) }
        }
        for string in strings {
            let bytes = string.utf8.count
            guard bytes <= remaining else { return false }
            remaining -= bytes
        }
        return true
    }

    private static func decode(_ data: Data, question: DecisionChoiceQuestion) throws -> DecisionChoiceResult {
        guard data.count <= maximumResponseBytes,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.answers.count == 1, let answer = response.answers.first,
              answer.name == question.name
        else { throw DecisionsClientError.invalidResponse }
        if answer.type == "refusal" { return .refusal }
        guard answer.type == "choice", let choice = answer.choice,
              let confidence = answer.confidence, validProbability(confidence),
              let probabilities = answer.probabilities,
              validProbabilities(probabilities, choices: question.choices),
              question.choices.contains(where: { $0.value == choice })
        else { throw DecisionsClientError.invalidResponse }
        return .choice(DecisionChoiceAnswer(
                        choice: choice, confidence: confidence, probabilities: probabilities))
    }

    private static func validProbabilities(
        _ probabilities: [DecisionChoiceProbability], choices: [DecisionChoiceOption]
    ) -> Bool {
        let values = probabilities.map(\.value)
        return probabilities.count == choices.count
            && Set(values).count == values.count
            && Set(values) == Set(choices.map(\.value))
            && probabilities.allSatisfy { validProbability($0.probability) }
            && abs(probabilities.reduce(0) { $0 + $1.probability } - 1) <= 0.001
    }

    private static func validProbability(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    private static func checkStatus(_ status: Int) throws {
        switch status {
        case 200: return
        case 401, 403: throw DecisionsClientError.unauthorized
        case 408, 504: throw DecisionsClientError.timedOut
        case 429: throw DecisionsClientError.rateLimited
        case 500...599: throw DecisionsClientError.serviceUnavailable
        default: throw DecisionsClientError.httpStatus(status)
        }
    }
}
