import XCTest

@testable import Rede

/// MEM-2 "Verbesserungs-Erkennung" core: pins the pure `ImprovementDiff.observe` matcher.
/// Conservative by design — it must report `changed=false` for verbatim, recover the edited text
/// when our insertion was corrected in place, and return `nil` (don't guess) when our text can't be
/// located or the field holds unrelated content. No AX / AppKit state is touched.
final class ImprovementDiffTests: XCTestCase {

  // MARK: - Verbatim → unchanged

  func testInsertedFoundVerbatimIsUnchanged() {
    let inserted = "Hallo, das ist ein Test."
    let result = ImprovementDiff.observe(inserted: inserted, fieldValue: inserted)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.changed, false)
    XCTAssertEqual(result?.finalText, inserted)
  }

  func testVerbatimWithSurroundingFieldTextIsUnchanged() {
    let inserted = "Bitte um Rückmeldung bis Freitag."
    let field = "Hi Tom,\n\n\(inserted)\n\nViele Grüße"
    let result = ImprovementDiff.observe(inserted: inserted, fieldValue: field)
    XCTAssertEqual(result?.changed, false)
    XCTAssertEqual(result?.finalText, inserted)
  }

  // MARK: - Whitespace-normalized match → unchanged

  func testWhitespaceNormalizedMatchIsUnchanged() {
    let inserted = "Das  ist   ein\nTest."
    let field = "Das ist ein Test."
    let result = ImprovementDiff.observe(inserted: inserted, fieldValue: field)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.changed, false)
  }

  // MARK: - Edited in place → recovers the edited text

  func testInsertedEditedInPlaceReturnsEditedFinalText() {
    let inserted = "Ich melde mich morgen bei dir wegen dem Projekt."
    // User fixed "wegen dem" → "wegen des" and kept the rest.
    let field = "Ich melde mich morgen bei dir wegen des Projekts."
    let result = ImprovementDiff.observe(inserted: inserted, fieldValue: field)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.changed, true)
    XCTAssertEqual(result?.finalText, field)
  }

  func testEditedRegionRecoveredWithinSurroundingText() {
    let inserted = "Können wir das Meeting auf 15 Uhr verschieben?"
    // Edited inside a larger field; word swapped, stable head + tail intact.
    let edited = "Können wir das Meeting auf 16 Uhr verschieben?"
    let field = "Hallo,\n\(edited)\nDanke!"
    let result = ImprovementDiff.observe(inserted: inserted, fieldValue: field)
    XCTAssertEqual(result?.changed, true)
    XCTAssertEqual(result?.finalText, edited)
  }

  // MARK: - Not found → nil (don't guess)

  func testInsertedNotFoundReturnsNil() {
    let inserted = "Hallo, das ist ein Test."
    let field = "Völlig anderer Inhalt, der nichts damit zu tun hat."
    XCTAssertNil(ImprovementDiff.observe(inserted: inserted, fieldValue: field))
  }

  func testEmptyFieldReturnsNil() {
    XCTAssertNil(ImprovementDiff.observe(inserted: "Etwas Text.", fieldValue: ""))
  }

  func testEmptyInsertedReturnsNil() {
    XCTAssertNil(ImprovementDiff.observe(inserted: "   \n  ", fieldValue: "Irgendwas steht hier."))
  }

  // MARK: - Similarity guard: unrelated content between weak anchors is NOT an edit

  func testUnrelatedFieldContentReturnsNil() {
    // Shares only a trivial leading/trailing fragment ("D"/"."), but the body is unrelated — the
    // similarity guard must reject it rather than reporting a bogus "edit".
    let inserted = "Der Bericht ist fertig und liegt im geteilten Ordner."
    let field = "Die Katze schläft den ganzen Tag auf dem Sofa."
    XCTAssertNil(ImprovementDiff.observe(inserted: inserted, fieldValue: field))
  }

  func testTotallyReplacedTextReturnsNil() {
    let inserted = "Termin am Dienstag bestätigt."
    let field = "Mittagessen war lecker."
    XCTAssertNil(ImprovementDiff.observe(inserted: inserted, fieldValue: field))
  }

  // MARK: - Large-input guard (R3-DR-axcap)

  func testVerbatimStillDetectedOnOversizedField() {
    // The cheap verbatim check runs BEFORE the size guard, so an unchanged insertion in a huge
    // field is still recognized as unchanged (no expensive anchoring needed).
    let inserted = "Das ist mein eingefügter Satz."
    let field = String(repeating: "x", count: ImprovementDiff.maxDiffInputLength + 500) + inserted
    let result = ImprovementDiff.observe(inserted: inserted, fieldValue: field)
    XCTAssertEqual(result?.changed, false)
  }

  func testOversizedEditedFieldSkipsExpensiveRecovery() {
    // An edited (non-verbatim) insertion inside an oversized field must NOT trigger the O(n²) anchor
    // scan — above the cap `observe` returns nil instead of recovering the edit.
    let inserted = "Hallo Welt, das ist ein Test."
    let edited = "Hallo Welt, das war ein Test."  // one-word change → would normally be recovered
    let field = String(repeating: "y", count: ImprovementDiff.maxDiffInputLength + 1) + edited
    XCTAssertNil(ImprovementDiff.observe(inserted: inserted, fieldValue: field))
  }

  // MARK: - Similarity helper sanity

  func testSimilarityHighForSmallEdit() {
    let lhs = "Ich melde mich morgen bei dir wegen dem Projekt"
    let rhs = "Ich melde mich morgen bei dir wegen des Projekts"
    XCTAssertGreaterThanOrEqual(
      ImprovementDiff.similarity(lhs, rhs), ImprovementDiff.minimumSimilarity)
  }

  func testSimilarityLowForUnrelatedText() {
    let lhs = "Der Bericht ist fertig und liegt im Ordner"
    let rhs = "Die Katze schläft auf dem Sofa"
    XCTAssertLessThan(ImprovementDiff.similarity(lhs, rhs), ImprovementDiff.minimumSimilarity)
  }
}
