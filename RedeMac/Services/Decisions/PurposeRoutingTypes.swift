import Foundation

enum DictationPurpose: String, CaseIterable, Sendable { case email, aiPrompt = "ai_prompt", other }

struct DecisionContext: Equatable, Sendable {
    var dictatedText: String
    var selectedText: String?
    var appName: String?
    var fieldText: String?
}

enum NeutralReason: String, Sendable {
    case notEligible, remoteNotAllowed, noAPIKey, tooShort, timeout, transport
    case refusal, invalidChoice, lowConfidence, lowMargin, cancelled
}

struct PurposeDecision: Equatable, Sendable {
    let purpose: DictationPurpose
    let confidence: Double?
    let neutralReason: NeutralReason?
    /// Cancellation is terminal: callers must abort before rewriting or producing any output.
    var isCancelled: Bool { neutralReason == .cancelled }

    static func neutral(_ reason: NeutralReason, confidence: Double? = nil) -> PurposeDecision {
        PurposeDecision(purpose: .other, confidence: confidence, neutralReason: reason)
    }
}

struct PurposeRoutingPolicy: Sendable {
    var minConfidence = 0.55
    var minMargin = 0.15
    var minWords = 4
    var timeout: Duration = .seconds(2.5)
}

protocol PurposeRouting: Sendable {
    func route(_ context: DecisionContext) async -> PurposeDecision
}

enum PurposeRoutingEligibility {
    // Contract labels are shared with the integration lane.
    // swiftlint:disable:next function_parameter_count inclusive_language
    static func resolve(masterEnabled: Bool, modeAutomatic: Bool, secureLocal: Bool,
                        rewriteIsOpenAI: Bool, kindRewrites: Bool, hasAPIKey: Bool) -> NeutralReason? {
        if secureLocal { return .remoteNotAllowed }
        if !masterEnabled || !modeAutomatic || !rewriteIsOpenAI || !kindRewrites { return .notEligible }
        return hasAPIKey ? nil : .noAPIKey
    }
}
