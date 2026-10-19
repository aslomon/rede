import Foundation

/// Counts attempts separately from required successful acknowledgements; error IDs identify only client events.
struct LiveCommitLedger {
    private var attempts = Set<String>()
    private var rejected = Set<String>()
    private var acknowledgedItems = Set<String>()
    var requiredAcknowledgements: Int { attempts.count - rejected.count }
    var receivedAcknowledgements: Int { acknowledgedItems.count }
    var allAttemptsRejected: Bool { !attempts.isEmpty && requiredAcknowledgements == 0 }
    var isComplete: Bool { requiredAcknowledgements > 0 && receivedAcknowledgements == requiredAcknowledgements }

    mutating func beginAttempt() -> String {
        let eventID = UUID().uuidString
        attempts.insert(eventID)
        return eventID
    }

    mutating func acknowledge(itemID: String) {
        acknowledgedItems.insert(itemID)
    }

    mutating func rejectEmpty(eventID: String?) {
        guard let eventID, attempts.contains(eventID), !rejected.contains(eventID),
              receivedAcknowledgements < requiredAcknowledgements else { return }
        rejected.insert(eventID)
    }
}
