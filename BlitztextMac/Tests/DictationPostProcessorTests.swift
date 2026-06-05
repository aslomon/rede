import XCTest

@testable import Blitztext

/// Pure-logic tests for `DictationPostProcessor`: literal replacements (whole-word vs substring,
/// casing), spoken-punctuation mapping (attaching to the preceding word, no leading space,
/// newlines), the empty/no-op guard and inline double-space collapse.
final class DictationPostProcessorTests: XCTestCase {

  private func dictionary(
    _ replacements: [DictationReplacement] = [],
    punctuation: Bool = false
  ) -> DictationDictionary {
    DictationDictionary(replacements: replacements, spokenPunctuationEnabled: punctuation)
  }

  // MARK: - Default

  /// Spoken punctuation MUST default OFF so dictating real words like "der wichtigste Punkt"
  /// is never silently mapped to a symbol. Guards the data-corruption default.
  func testSpokenPunctuationDefaultsOff() {
    XCTAssertFalse(DictationDictionary().spokenPunctuationEnabled)
    XCTAssertFalse(DictationDictionary(replacements: []).spokenPunctuationEnabled)
  }

  // MARK: - No-op guard

  func testEmptyDictionaryIsNoOp() {
    let input = "Komma das bleibt unverändert"
    let result = DictationPostProcessor.process(input, dictionary: dictionary())
    XCTAssertEqual(result, input)
  }

  func testNoOpReturnsTextUnchangedEvenWithSpokenTokens() {
    // punctuation off + no replacements -> the spoken token must NOT be mapped.
    let result = DictationPostProcessor.process(
      "Hallo Komma Welt", dictionary: dictionary(punctuation: false))
    XCTAssertEqual(result, "Hallo Komma Welt")
  }

  // MARK: - Literal whole-word replacement + casing

  func testWholeWordReplacementUsesUserCasing() {
    let dict = dictionary([DictationReplacement(from: "blitztext", to: "Blitztext")])
    let result = DictationPostProcessor.process("ich nutze blitztext täglich", dictionary: dict)
    XCTAssertEqual(result, "ich nutze Blitztext täglich")
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

  // MARK: - Spoken punctuation attaching to preceding word

  func testKommaAttachesToPrecedingWordWithoutLeadingSpace() {
    let result = DictationPostProcessor.process(
      "Hallo Komma wie geht es dir Fragezeichen", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Hallo, wie geht es dir?")
  }

  func testPunktAndAusrufezeichenAttach() {
    let result = DictationPostProcessor.process(
      "Das ist gut Punkt Super Ausrufezeichen", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Das ist gut. Super!")
  }

  func testDoppelpunktAndSemikolonAttach() {
    let result = DictationPostProcessor.process(
      "Liste Doppelpunkt eins Semikolon zwei", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Liste: eins; zwei")
  }

  func testStrichpunktMapsToSemicolon() {
    let result = DictationPostProcessor.process(
      "eins Strichpunkt zwei", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "eins; zwei")
  }

  func testBindestrichMapsToHyphen() {
    let result = DictationPostProcessor.process(
      "schwarz Bindestrich weiß", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "schwarz - weiß")
  }

  func testSpokenPunctuationIsCaseInsensitive() {
    let result = DictationPostProcessor.process(
      "Hallo KOMMA Welt", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Hallo, Welt")
  }

  // MARK: - newline mapping

  func testNeueZeileMapsToNewline() {
    let result = DictationPostProcessor.process(
      "Zeile eins neue Zeile Zeile zwei", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Zeile eins\nZeile zwei")
  }

  func testNeuerAbsatzMapsToNewline() {
    let result = DictationPostProcessor.process(
      "Absatz eins neuer Absatz Absatz zwei", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Absatz eins\nAbsatz zwei")
  }

  // MARK: - Spoken token must not match inside other words

  func testSpokenTokenNotReplacedInsideOtherWords() {
    // "Kommando" contains "komma" — whole-word matching must leave it untouched.
    let result = DictationPostProcessor.process(
      "Das Kommando steht Komma jetzt", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Das Kommando steht, jetzt")
  }

  // MARK: - Double-space collapse

  func testDoubleSpacesCollapseAfterPunctuationMapping() {
    // The removed token leaves a double space that must collapse to one.
    let result = DictationPostProcessor.process(
      "Hallo  Komma   Welt", dictionary: dictionary(punctuation: true))
    XCTAssertEqual(result, "Hallo, Welt")
  }

  // MARK: - Combined order: replacements then punctuation

  func testReplacementsRunBeforePunctuation() {
    let dict = DictationDictionary(
      replacements: [DictationReplacement(from: "blitztext", to: "Blitztext")],
      spokenPunctuationEnabled: true
    )
    let result = DictationPostProcessor.process(
      "ich nutze blitztext Punkt", dictionary: dict)
    XCTAssertEqual(result, "ich nutze Blitztext.")
  }
}
