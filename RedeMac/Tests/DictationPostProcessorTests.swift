import XCTest

@testable import Rede

/// Pure-logic tests for `DictationPostProcessor`: literal replacements (whole-word vs substring,
/// casing, German umlaut/ß boundaries) and the empty/no-op guard.
final class DictationPostProcessorTests: XCTestCase {

  private func dictionary(_ replacements: [DictationReplacement] = []) -> DictationDictionary {
    DictationDictionary(replacements: replacements)
  }

  // MARK: - No-op guard

  func testEmptyDictionaryIsNoOp() {
    let input = "das bleibt unverändert"
    let result = DictationPostProcessor.process(input, dictionary: dictionary())
    XCTAssertEqual(result, input)
  }

  // MARK: - Literal whole-word replacement + casing

  func testWholeWordReplacementUsesUserCasing() {
    let dict = dictionary([DictationReplacement(from: "notabene", to: "Notabene")])
    let result = DictationPostProcessor.process("ich nutze notabene täglich", dictionary: dict)
    XCTAssertEqual(result, "ich nutze Notabene täglich")
  }

  func testWholeWordReplacementIsCaseInsensitiveMatch() {
    let dict = dictionary([DictationReplacement(from: "Github", to: "GitHub")])
    let result = DictationPostProcessor.process("siehe GITHUB und github", dictionary: dict)
    XCTAssertEqual(result, "siehe GitHub und GitHub")
  }

  func testWholeWordDoesNotMatchInsideOtherWords() {
    let dict = dictionary([DictationReplacement(from: "rat", to: "Rad")])
    // "Beratung" / "Verrat" must stay intact; only the standalone "rat" is replaced.
    let result = DictationPostProcessor.process("Beratung und rat und Verrat", dictionary: dict)
    XCTAssertEqual(result, "Beratung und Rad und Verrat")
  }

  // MARK: - Umlaut / ß word boundaries (R4-DR-miner-umlaut-boundary regression)
  // The miner can learn `from` cores with German umlauts/ß. These pin that ICU's `\b` sets word
  // boundaries correctly around non-ASCII letters at the START, MIDDLE and END of a term.

  func testWholeWordMatchesUmlautAtStart() {
    let dict = dictionary([DictationReplacement(from: "Öl", to: "Oel")])
    XCTAssertEqual(
      DictationPostProcessor.process("das Öl ist teuer", dictionary: dict), "das Oel ist teuer")
  }

  func testWholeWordMatchesUmlautInMiddle() {
    let dict = dictionary([DictationReplacement(from: "Müller", to: "Mueller")])
    XCTAssertEqual(
      DictationPostProcessor.process("Frau Müller kommt", dictionary: dict), "Frau Mueller kommt")
  }

  func testWholeWordMatchesEszettAtEnd() {
    let dict = dictionary([DictationReplacement(from: "Fuß", to: "Fuss")])
    XCTAssertEqual(
      DictationPostProcessor.process("mein Fuß tut weh", dictionary: dict), "mein Fuss tut weh")
  }

  func testWholeWordEszettDoesNotMatchInsideWord() {
    let dict = dictionary([DictationReplacement(from: "Fuß", to: "Fuss")])
    // The ß→b boundary must hold: "Fußball" stays intact.
    XCTAssertEqual(
      DictationPostProcessor.process("der Fußball rollt", dictionary: dict), "der Fußball rollt")
  }

  // MARK: - Substring replacement

  func testSubstringReplacementMatchesInsideWords() {
    let dict = dictionary([DictationReplacement(from: "ue", to: "ü", wholeWord: false)])
    let result = DictationPostProcessor.process("Mueller gruesst", dictionary: dict)
    XCTAssertEqual(result, "Müller grüsst")
  }

  func testSubstringPreservesSurroundingSpacing() {
    let dict = dictionary([DictationReplacement(from: "foo", to: "bar", wholeWord: false)])
    let result = DictationPostProcessor.process("a foo b", dictionary: dict)
    XCTAssertEqual(result, "a bar b")
  }
}
