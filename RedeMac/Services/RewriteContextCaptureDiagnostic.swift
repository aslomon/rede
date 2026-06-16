import Foundation

struct RewriteContextCaptureDiagnostic: Equatable {
  let modeID: ModeConfig.ID
  let launchSource: WorkflowLaunchSource
  let selectionEnabled: Bool
  let selectionPresent: Bool
  let selectionSelectedChars: Int
  let selectionSurroundingChars: Int
  let automaticEnabled: Bool
  let automaticPresent: Bool
  let automaticChars: Int
  let automaticAppName: String
  let automaticBundleID: String
  let automaticWindowTitlePresent: Bool
  let targetAppName: String
  let targetBundleID: String
  let targetWindowTitlePresent: Bool

  init(
    modeID: ModeConfig.ID,
    launchSource: WorkflowLaunchSource,
    config: ModeConfig,
    selection: SelectionContext?,
    automaticContext: AutomaticRewriteContext?,
    targetAppName: String? = nil,
    targetBundleID: String? = nil,
    targetWindowTitle: String? = nil
  ) {
    self.modeID = modeID
    self.launchSource = launchSource
    self.selectionEnabled = config.slot == .textImprover && config.rewrite.replyContextMode != .off
    self.selectionPresent = !(selection?.isEmpty ?? true)
    self.selectionSelectedChars = Self.trimmedCount(selection?.selectedText)
    self.selectionSurroundingChars = Self.trimmedCount(selection?.surroundingText)
    self.automaticEnabled =
      (config.slot == .textImprover || config.slot == .dampfAblassen)
      && config.rewrite.useAutomaticFieldContext
    self.automaticPresent = !(automaticContext?.isEmpty ?? true)
    self.automaticChars = Self.trimmedCount(automaticContext?.text)
    self.automaticAppName = Self.publicValue(automaticContext?.appName)
    self.automaticBundleID = Self.publicValue(automaticContext?.appBundleID)
    self.automaticWindowTitlePresent =
      !((automaticContext?.windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty)
    self.targetAppName = Self.publicValue(targetAppName)
    self.targetBundleID = Self.publicValue(targetBundleID)
    self.targetWindowTitlePresent =
      !((targetWindowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  var logLine: String {
    [
      "modeID=\(modeID)",
      "source=\(launchSource.logLabel)",
      "selectionEnabled=\(selectionEnabled)",
      "selectionPresent=\(selectionPresent)",
      "selectionSelectedChars=\(selectionSelectedChars)",
      "selectionSurroundingChars=\(selectionSurroundingChars)",
      "automaticEnabled=\(automaticEnabled)",
      "automaticPresent=\(automaticPresent)",
      "automaticChars=\(automaticChars)",
      "automaticApp=\(automaticAppName)",
      "automaticBundle=\(automaticBundleID)",
      "automaticWindowTitlePresent=\(automaticWindowTitlePresent)",
      "targetApp=\(targetAppName)",
      "targetBundle=\(targetBundleID)",
      "targetWindowTitlePresent=\(targetWindowTitlePresent)",
    ].joined(separator: " ")
  }

  private static func trimmedCount(_ value: String?) -> Int {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
  }

  private static func publicValue(_ value: String?) -> String {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "none" : trimmed
  }
}

private extension WorkflowLaunchSource {
  var logLabel: String {
    switch self {
    case .manual: return "manual"
    case .hotkeyBackground: return "hotkeyBackground"
    }
  }
}
