import Foundation

// MARK: - Rewrite-capability (FT-3 "Archiv wiederverwenden")

extension WorkflowType {
  /// The modes whose pipeline ends in an LLM rewrite step and can therefore be re-run on a stored
  /// raw transcript WITHOUT a new recording. Plain transcription has nothing to re-run.
  /// Pure + static so the archive UI and tests can list them without an `AppState`.
  static let rewriteCapableModes: [WorkflowType] = [.textImprover, .dampfAblassen, .emojiText]

  /// True when this slot runs an LLM rewrite step that can be re-applied to a raw transcript.
  var isRewriteCapable: Bool { Self.rewriteCapableModes.contains(self) }
}

// MARK: - Prompt selection for a re-run

/// Builds the system prompt for a re-run, mirroring exactly what each live workflow does:
/// the Emoji slot uses `emojiSystemPrompt`, every other rewrite slot uses `rewriteSystemPrompt`.
/// Pure (no `AppState`, no SwiftUI) so it stays unit-testable.
enum RewriteReuse {
  /// Picks the same prompt the live workflow would build for `kind`. `selection` is always nil for
  /// a re-run (the archive has no live frontmost selection), so reply/edit context never applies.
  static func systemPrompt(
    kind: ModeKind,
    rewrite: RewriteConfig,
    customTerms: [String],
    memory: MemoryContext?,
    userIdentity: UserIdentityContext? = nil
  ) -> String {
    switch kind {
    case .transcribeThenEmoji:
      return LLMService.emojiSystemPrompt(rewrite, customTerms: customTerms)
    case .transcribeThenRewrite, .transcribeOnly:
      return LLMService.rewriteSystemPrompt(
        rewrite,
        customTerms: customTerms,
        selection: nil,
        memory: memory,
        userIdentity: userIdentity
      )
    }
  }
}
