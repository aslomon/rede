import Foundation

/// One selectable rewrite model. `badge` is a semantic marker; the view maps it to German copy.
struct ModelPickerOption: Identifiable, Equatable {
  enum Badge: Equatable { case recommended, custom, account }

  let option: RewriteModelOption
  let badge: Badge?
  var id: String { option.id }
}

/// Pure presentation + edit logic for the model and reasoning-effort controls of a rewrite mode.
/// No view code. It never changes a stored model on its own: every edit returns a new config.
struct ModelPickerModel {
  let config: RewriteConfig
  /// Extra chat model ids fetched from the user's account (empty until fetched).
  let accountModelIDs: [String]

  init(config: RewriteConfig, accountModelIDs: [String] = []) {
    self.config = config
    self.accountModelIDs = accountModelIDs
  }

  // MARK: - Models

  /// Curated models in their fixed order (Luna first), then account models, then — only when the
  /// stored id is none of those — the stored id itself as "Eigenes", so it is never silently lost.
  var options: [ModelPickerOption] {
    var result = RewriteModelRegistry.options(includingFetched: accountModelIDs).map { option in
      ModelPickerOption(option: option, badge: badge(for: option))
    }
    if !result.contains(where: { $0.id == config.modelID }) {
      result.append(
        ModelPickerOption(option: RewriteModelRegistry.option(for: config.modelID), badge: .custom))
    }
    return result
  }

  var selectedModelID: String { config.modelID }

  private func badge(for option: RewriteModelOption) -> ModelPickerOption.Badge? {
    if option.id == RewriteModelRegistry.recommendedModelID { return .recommended }
    return RewriteModelRegistry.curated.contains(where: { $0.id == option.id }) ? nil : .account
  }

  // MARK: - Reasoning effort

  /// The efforts the user may pick for the current model. Empty means "not applicable": the
  /// control is hidden and nothing is sent.
  var selectableEfforts: [RewriteReasoningEffort] {
    RewriteModelRegistry.selectableEfforts(for: config.modelID)
  }

  var showsEffortControl: Bool { !selectableEfforts.isEmpty }

  /// The picker rows in order. `nil` is the model default and is offered only where an unset effort
  /// sends nothing (Sol: the API default applies). Luna's unset effort resolves to an explicit
  /// `none`, which is already a row, so it gets no extra one; the default row is never `aus`.
  var effortChoices: [RewriteReasoningEffort?] {
    var choices = selectableEfforts.map { Optional($0) }
    let unsetSendsNothing =
      RewriteModelRegistry.resolvedEffort(modelID: config.modelID, stored: nil) == nil
    if !choices.isEmpty, unsetSendsNothing { choices.insert(nil, at: 0) }
    return choices
  }

  /// What will actually be sent: the stored value when supported, else the model default. It is
  /// also the picker selection: `nil` (nothing sent) selects the model-default row.
  var effectiveEffort: RewriteReasoningEffort? {
    RewriteModelRegistry.resolvedEffort(modelID: config.modelID, stored: config.reasoningEffort)
  }

  /// Higher levels think longer, so the view adds a "dauert länger" hint for them.
  var effectiveEffortIsSlow: Bool {
    switch effectiveEffort {
    case .high, .xhigh, .max: return true
    default: return false
    }
  }

  // MARK: - Edits

  /// Switches the model. A stored effort the new model does not support is dropped (not kept
  /// dormant), so a later switch back never resurrects a stale choice.
  func selecting(modelID: String) -> RewriteConfig {
    var updated = config
    updated.modelID = modelID
    let supported = RewriteModelRegistry.supportedEfforts(for: modelID)
    if let stored = updated.reasoningEffort, !supported.contains(stored) {
      updated.reasoningEffort = nil
    }
    return updated
  }

  /// Stores an explicit effort. Efforts outside the selectable set are ignored.
  func selecting(effort: RewriteReasoningEffort?) -> RewriteConfig {
    if let effort, !selectableEfforts.contains(effort) { return config }
    var updated = config
    updated.reasoningEffort = effort
    return updated
  }
}
