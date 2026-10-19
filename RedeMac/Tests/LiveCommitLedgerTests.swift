import XCTest
@testable import Rede

final class LiveCommitLedgerTests: XCTestCase {
    func testOnlyCorrelatedEmptyRejectionRemovesOneRequiredAcknowledgement() {
        var ledger = LiveCommitLedger()
        let rejected = ledger.beginAttempt()
        _ = ledger.beginAttempt()
        ledger.rejectEmpty(eventID: "unrelated")
        ledger.rejectEmpty(eventID: nil)
        XCTAssertEqual(ledger.requiredAcknowledgements, 2)
        ledger.rejectEmpty(eventID: rejected)
        ledger.rejectEmpty(eventID: rejected)
        XCTAssertEqual(ledger.requiredAcknowledgements, 1)
        ledger.acknowledge(itemID: "valid-item")
        ledger.acknowledge(itemID: "valid-item")
        XCTAssertEqual(ledger.receivedAcknowledgements, 1)
        XCTAssertTrue(ledger.isComplete)
    }

    func testDelayedEmptyErrorAfterLaterValidAcknowledgementStillCompletes() {
        var ledger = LiveCommitLedger()
        let rejected = ledger.beginAttempt()
        _ = ledger.beginAttempt()
        ledger.acknowledge(itemID: "valid-item")
        XCTAssertFalse(ledger.isComplete)
        ledger.rejectEmpty(eventID: rejected)
        XCTAssertTrue(ledger.isComplete)
    }

    func testAcknowledgedValidAttemptCannotBeRemovedByAnExtraEmptyError() {
        var ledger = LiveCommitLedger()
        let attempt = ledger.beginAttempt()
        ledger.acknowledge(itemID: "valid-item")
        ledger.rejectEmpty(eventID: attempt)
        XCTAssertEqual(ledger.requiredAcknowledgements, 1)
        XCTAssertTrue(ledger.isComplete)
    }
}
