import XCTest

@testable import Rede

/// The effort picker must always bind to a row it offers. An unset effort is the model default:
/// Luna sends an explicit `none` ("aus"), Sol and 6.1 Sol send nothing ("modellstandard").
@MainActor
final class EffortPickerChoicesTests: XCTestCase {
  private func picker(_ modelID: String, stored: RewriteReasoningEffort? = nil) -> ModelPickerModel
  {
    var config = RewriteConfig()
    config.modelID = modelID
    config.reasoningEffort = stored
    return ModelPickerModel(config: config)
  }

  /// `nil` stands for the model-default row; the rest are explicit efforts.
  private func rows(
    modelDefault: Bool, _ efforts: [RewriteReasoningEffort]
  ) -> [RewriteReasoningEffort?] {
    var result: [RewriteReasoningEffort?] = efforts.map { Optional($0) }
    if modelDefault { result.insert(nil, at: 0) }
    return result
  }

  func testLunaUnsetIsTheExplicitNoneRowAndGetsNoModelDefaultRow() {
    let luna = picker("gpt-6-luna")

    XCTAssertEqual(luna.effortChoices, rows(modelDefault: false, [.none, .medium, .high, .xhigh]))
    XCTAssertEqual(luna.effectiveEffort, RewriteReasoningEffort.none)
    XCTAssertTrue(luna.effortChoices.contains(luna.effectiveEffort))
    XCTAssertEqual(RewriteEffortControl.label(for: luna.effectiveEffort), "aus")
    XCTAssertEqual(
      RewriteModelRegistry.resolvedEffort(modelID: "gpt-6-luna", stored: nil),
      RewriteReasoningEffort.none, "Luna still sends none when nothing is stored")
  }

  func testSolUnsetSelectsTheModelDefaultRowNotAus() {
    let sol = picker("gpt-6-sol")

    XCTAssertEqual(
      sol.effortChoices,
      rows(modelDefault: true, [.none, .low, .medium, .high, .xhigh, .max]))
    XCTAssertNil(sol.effectiveEffort, "nothing is sent, so the default row is selected")
    XCTAssertTrue(sol.effortChoices.contains(sol.effectiveEffort))
    XCTAssertEqual(RewriteEffortControl.label(for: sol.effectiveEffort), "modellstandard")
    XCTAssertNotEqual(
      RewriteEffortControl.label(for: sol.effectiveEffort),
      RewriteEffortControl.label(for: RewriteReasoningEffort.none))
    XCTAssertNil(RewriteModelRegistry.resolvedEffort(modelID: "gpt-6-sol", stored: nil))
  }

  func testSixPointOneSolUnsetSelectsAnOfferedRowAndNeverOffersNone() {
    let sol61 = picker("gpt-6.1-sol")

    XCTAssertEqual(
      sol61.effortChoices, rows(modelDefault: true, [.low, .medium, .high, .xhigh, .max]))
    XCTAssertFalse(sol61.effortChoices.contains(RewriteReasoningEffort.none))
    XCTAssertNil(sol61.effectiveEffort)
    XCTAssertTrue(
      sol61.effortChoices.contains(sol61.effectiveEffort),
      "the old binding fell back to `none`, which this model does not offer")
    XCTAssertNil(RewriteModelRegistry.resolvedEffort(modelID: "gpt-6.1-sol", stored: nil))
  }

  func testShowingTheDefaultRowNeverWritesTheStoredConfig() {
    for model in ["gpt-6-sol", "gpt-6.1-sol"] {
      let before = picker(model)
      _ = before.effortChoices
      _ = before.effectiveEffort

      XCTAssertNil(before.config.reasoningEffort, model)
      XCTAssertNil(
        before.selecting(effort: nil).reasoningEffort, "picking the default row: \(model)")
    }
  }

  func testSolKeepsAusAndTheModelDefaultApartAndRoundTripsBetweenThem() {
    let sol = picker("gpt-6-sol")

    let aus = sol.selecting(effort: RewriteReasoningEffort.none)
    XCTAssertEqual(aus.reasoningEffort, RewriteReasoningEffort.none)
    XCTAssertEqual(ModelPickerModel(config: aus).effectiveEffort, RewriteReasoningEffort.none)

    let cleared = ModelPickerModel(config: aus).selecting(effort: nil)
    XCTAssertNil(cleared.reasoningEffort)
    XCTAssertNil(ModelPickerModel(config: cleared).effectiveEffort)
  }

  func testSixPointOneSolIgnoresNoneAndKeepsAnExplicitChoice() {
    let sol61 = picker("gpt-6.1-sol")
    XCTAssertNil(sol61.selecting(effort: RewriteReasoningEffort.none).reasoningEffort)

    let high = picker("gpt-6.1-sol", stored: .high)
    XCTAssertEqual(high.effectiveEffort, .high)
    XCTAssertTrue(high.effortChoices.contains(high.effectiveEffort))
    XCTAssertEqual(high.config.reasoningEffort, .high, "reading never rewrites a stored choice")
  }

  func testModelsWithoutEffortsOfferNoRowsAtAll() {
    let legacy = picker("gpt-5.4")
    XCTAssertTrue(legacy.effortChoices.isEmpty)
    XCTAssertFalse(legacy.showsEffortControl)
  }
}
