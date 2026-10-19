import Foundation

// MARK: - Rewrite outcome

/// Result of a single rewrite call. Carries the produced `text` plus the model that was REQUESTED
/// and the model that ACTUALLY ran. They differ only when the OpenAI provider fell back after the
/// chosen model was rejected — that gap is what the UI surfaces so a silent quality drop is visible.
struct RewriteOutcome: Equatable, Sendable {
  let text: String
  let variants: [String]
  /// The model that actually produced `text`. `nil` only when the provider can't name one.
  let usedModelID: String?
  /// The model the caller asked for. `nil` only when the provider can't name one.
  let requestedModelID: String?

  init(
    text: String,
    variants: [String]? = nil,
    usedModelID: String?,
    requestedModelID: String?
  ) {
    self.text = text
    self.variants = variants ?? [text]
    self.usedModelID = usedModelID
    self.requestedModelID = requestedModelID
  }

  /// True when the effective model differs from the requested one (a fallback happened).
  var didFallBack: Bool {
    guard let usedModelID, let requestedModelID else { return false }
    return usedModelID != requestedModelID
  }
}

// MARK: - Selection context (Phase 2)

/// Text the user had selected / surrounding the cursor in the frontmost app,
/// captured at recording start. In-memory only — never persisted.
struct SelectionContext: Sendable {
  var selectedText: String
  var surroundingText: String
  var appBundleID: String?

  var isEmpty: Bool {
    selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && surroundingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

// MARK: - Automatic rewrite context

/// Text from the focused input field, captured at recording start when the mode opts in.
/// In-memory only — never persisted. The text is capped before construction.
struct AutomaticRewriteContext: Sendable {
  var text: String
  var appBundleID: String?
  var appName: String?
  var windowTitle: String?

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

// MARK: - User identity context

/// Stable local identity of the person using rede. In-memory prompt context only; persisted in
/// `AppSettings.userDisplayName` so E-Mail/Prompt modes know from whose perspective they write.
struct UserIdentityContext: Sendable, Equatable {
  var displayName: String

  var isEmpty: Bool {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

// MARK: - Provider seam

/// Abstracts the rewrite transport so a mode can run on OpenAI or on-device.
/// Prompt-building stays in `LLMService`; a provider only turns
/// (systemPrompt, userText) into rewritten text.
protocol RewriteProvider: Sendable {
  func rewrite(systemPrompt: String, userText: String, temperature: Double) async throws
    -> RewriteOutcome
}
