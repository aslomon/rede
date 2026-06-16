import Foundation

enum HotkeyModifier: String, Codable, Sendable, CaseIterable, Hashable {
  case function
  case capsLock
  case shift
  case control
  case option
  case command

  static let displayOrder: [HotkeyModifier] = [
    .function, .capsLock, .shift, .control, .option, .command,
  ]

  var label: String {
    switch self {
    case .function: return "fn"
    case .capsLock: return "Caps"
    case .shift: return "Shift"
    case .control: return "Ctrl"
    case .option: return "Option"
    case .command: return "Cmd"
    }
  }
}

struct HotkeyKeyBinding: Codable, Sendable, Equatable, Hashable, Identifiable {
  var keyCode: UInt16
  var keyLabel: String

  var id: UInt16 { keyCode }
}

struct HotkeyConfig: Codable, Sendable, Equatable, Identifiable {
  var modeID: ModeConfig.ID
  var modifiers: [HotkeyModifier]
  var keys: [HotkeyKeyBinding]
  var isEnabled: Bool

  var id: ModeConfig.ID { modeID }

  var normalizedModifiers: [HotkeyModifier] {
    let selected = Set(modifiers)
    return HotkeyModifier.displayOrder.filter { selected.contains($0) }
  }

  var normalizedKeys: [HotkeyKeyBinding] {
    var seen = Set<UInt16>()
    var result: [HotkeyKeyBinding] = []
    for key in keys.sorted(by: { $0.keyCode < $1.keyCode }) {
      guard !seen.contains(key.keyCode) else { continue }
      seen.insert(key.keyCode)
      result.append(key)
    }
    return result
  }

  var labelParts: [String] {
    normalizedModifiers.map(\.label) + normalizedKeys.map(\.keyLabel)
  }

  var label: String {
    let parts = labelParts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return parts.isEmpty ? "nicht gesetzt" : parts.joined(separator: " + ")
  }

  var isConfigured: Bool {
    !normalizedModifiers.isEmpty || !normalizedKeys.isEmpty
  }

  var keyCode: UInt16? {
    get { normalizedKeys.first?.keyCode }
    set {
      guard let newValue else {
        keys = []
        return
      }
      let label = keyLabel ?? HotkeyKey.label(keyCode: newValue, characters: nil)
      keys = [HotkeyKeyBinding(keyCode: newValue, keyLabel: label)]
    }
  }

  var keyLabel: String? {
    get { normalizedKeys.first?.keyLabel }
    set {
      guard let first = normalizedKeys.first else { return }
      let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
      keys = [
        HotkeyKeyBinding(
          keyCode: first.keyCode,
          keyLabel: trimmed?.isEmpty == false ? trimmed ?? first.keyLabel : first.keyLabel
        )
      ]
    }
  }

  init(
    modeID: ModeConfig.ID,
    modifiers: [HotkeyModifier] = [],
    keyCode: UInt16? = nil,
    keyLabel: String? = nil,
    keys: [HotkeyKeyBinding] = [],
    isEnabled: Bool = true
  ) {
    self.modeID = modeID
    self.modifiers = modifiers
    if keys.isEmpty, let keyCode {
      self.keys = [
        HotkeyKeyBinding(
          keyCode: keyCode,
          keyLabel: keyLabel ?? HotkeyKey.label(keyCode: keyCode, characters: nil)
        )
      ]
    } else {
      self.keys = keys
    }
    self.isEnabled = isEnabled
  }

  enum CodingKeys: String, CodingKey {
    case modeID, modifiers, keys, keyCode, keyLabel, isEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    modeID = try container.decode(ModeConfig.ID.self, forKey: .modeID)
    modifiers = try container.decodeIfPresent([HotkeyModifier].self, forKey: .modifiers) ?? []
    if let decodedKeys = try container.decodeIfPresent([HotkeyKeyBinding].self, forKey: .keys) {
      keys = decodedKeys
    } else if let legacyKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode) {
      let legacyLabel = try container.decodeIfPresent(String.self, forKey: .keyLabel)
      keys = [
        HotkeyKeyBinding(
          keyCode: legacyKeyCode,
          keyLabel: legacyLabel ?? HotkeyKey.label(keyCode: legacyKeyCode, characters: nil)
        )
      ]
    } else {
      keys = []
    }
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(modeID, forKey: .modeID)
    try container.encode(modifiers, forKey: .modifiers)
    try container.encode(normalizedKeys, forKey: .keys)
    try container.encodeIfPresent(keyCode, forKey: .keyCode)
    try container.encodeIfPresent(keyLabel, forKey: .keyLabel)
    try container.encode(isEnabled, forKey: .isEnabled)
  }
}

enum HotkeyValidationIssue: Equatable {
  case duplicate(label: String, modeIDs: [ModeConfig.ID])
}

enum HotkeyRegistry {
  static func defaultConfig(modeID: ModeConfig.ID, slot: WorkflowType) -> HotkeyConfig {
    switch slot {
    case .transcription:
      return HotkeyConfig(modeID: modeID, modifiers: [.function, .shift])
    case .localTranscription:
      return HotkeyConfig(modeID: modeID, modifiers: [.function, .shift, .control])
    case .textImprover:
      return HotkeyConfig(modeID: modeID, modifiers: [.function, .control])
    case .dampfAblassen:
      return HotkeyConfig(modeID: modeID, modifiers: [.function, .option])
    case .emojiText:
      return HotkeyConfig(modeID: modeID, modifiers: [.function, .command])
    }
  }

  static func effectiveConfigs(
    for modes: [ModeConfig],
    stored: [ModeConfig.ID: HotkeyConfig]
  ) -> [ModeConfig.ID: HotkeyConfig] {
    var result: [ModeConfig.ID: HotkeyConfig] = [:]
    for mode in modes {
      if let config = stored[mode.id] {
        result[mode.id] = config
      } else if mode.id == mode.slot.rawValue {
        result[mode.id] = defaultConfig(modeID: mode.id, slot: mode.slot)
      } else {
        result[mode.id] = HotkeyConfig(modeID: mode.id, modifiers: [], isEnabled: false)
      }
    }
    return result
  }

  static func matchingModeID(
    modifiers: [HotkeyModifier],
    keyCode: UInt16? = nil,
    keyCodes: [UInt16] = [],
    configs: [ModeConfig.ID: HotkeyConfig]
  ) -> ModeConfig.ID? {
    let requested = Set(modifiers)
    let optionalKeyCodes = keyCode.map { [$0] } ?? []
    let requestedKeys = Set(keyCodes + optionalKeyCodes)
    guard !requested.isEmpty || !requestedKeys.isEmpty else { return nil }
    for modeID in configs.keys.sorted() {
      guard let config = configs[modeID], config.isEnabled else { continue }
      let configured = Set(config.normalizedModifiers)
      let configuredKeys = Set(config.normalizedKeys.map(\.keyCode))
      guard configuredKeys == requestedKeys, configured == requested else { continue }
      return modeID
    }
    return nil
  }

  static func hasPotentialMatch(
    modifiers: [HotkeyModifier],
    keyCodes: [UInt16],
    configs: [ModeConfig.ID: HotkeyConfig]
  ) -> Bool {
    let requestedModifiers = Set(modifiers)
    let requestedKeys = Set(keyCodes)
    guard !requestedKeys.isEmpty else { return false }
    return configs.values.contains { config in
      guard config.isEnabled else { return false }
      guard Set(config.normalizedModifiers) == requestedModifiers else { return false }
      let configuredKeys = Set(config.normalizedKeys.map(\.keyCode))
      return requestedKeys.isSubset(of: configuredKeys)
    }
  }

  static func validationIssues(configs: [ModeConfig.ID: HotkeyConfig]) -> [HotkeyValidationIssue] {
    let enabledConfigs = configs.values.filter { $0.isEnabled && $0.isConfigured }
    let grouped = Dictionary(grouping: enabledConfigs) { config in
      let modifierPart = config.normalizedModifiers.map(\.rawValue).joined(separator: "+")
      let keyPart =
        config.normalizedKeys.isEmpty
        ? "modifier-only"
        : config.normalizedKeys.map(\.keyCode).map(String.init).joined(separator: "+")
      return "\(modifierPart)|\(keyPart)"
    }

    return grouped.values.compactMap { group in
      let modeIDs = group.map(\.modeID).sorted()
      guard modeIDs.count > 1, let first = group.first else { return nil }
      return .duplicate(label: first.label, modeIDs: modeIDs)
    }
    .sorted { left, right in
      switch (left, right) {
      case let (.duplicate(leftLabel, leftIDs), .duplicate(rightLabel, rightIDs)):
        if leftLabel == rightLabel { return leftIDs.lexicographicallyPrecedes(rightIDs) }
        return leftLabel < rightLabel
      }
    }
  }

  static func conflictLabel(
    for candidate: HotkeyConfig,
    excluding modeID: ModeConfig.ID,
    configs: [ModeConfig.ID: HotkeyConfig]
  ) -> String? {
    guard candidate.isEnabled, candidate.isConfigured else { return nil }
    let candidateModifiers = Set(candidate.normalizedModifiers)
    let candidateKeys = Set(candidate.normalizedKeys.map(\.keyCode))
    for config in configs.values where config.modeID != modeID && config.isEnabled {
      guard config.isConfigured else { continue }
      guard Set(config.normalizedModifiers) == candidateModifiers else { continue }
      guard Set(config.normalizedKeys.map(\.keyCode)) == candidateKeys else { continue }
      return "konflikt: \(candidate.label) ist bereits belegt."
    }
    return nil
  }
}
