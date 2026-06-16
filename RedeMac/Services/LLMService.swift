import Foundation

enum LLMError: LocalizedError {
  case notConfigured
  case networkError(String)
  case apiError(String)
  case noContent
  case modelUnavailable(String)
  case localModelUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
    case .networkError(let msg):
      return "Verbindungsproblem: \(msg)"
    case .apiError(let msg):
      return "Fehler von OpenAI: \(msg)"
    case .noContent:
      return "Keine Antwort erhalten. Bitte nochmal versuchen."
    case .modelUnavailable(let model):
      return "Modell \(model) ist auf deinem OpenAI-Account nicht verfügbar."
    case .localModelUnavailable(let reason):
      return reason
    }
  }
}

/// Builds the system prompts for the rewrite step. Transport lives in the
/// `RewriteProvider` implementations; this stays the durable, provider-agnostic asset.
enum LLMService {
  /// Default rewrite temperature (providers omit it for models that don't support it).
  static let defaultRewriteTemperature = 0.3

  // MARK: - Rewrite prompt (E-Mail / Prompt / generischer Verbesserer)

  static func rewriteSystemPrompt(
    _ rewrite: RewriteConfig,
    customTerms: [String],
    selection: SelectionContext?,
    automaticContext: AutomaticRewriteContext? = nil,
    memory: MemoryContext? = nil,
    userIdentity: UserIdentityContext? = nil,
    emailMemory: EmailSemanticMemoryContext? = nil
  ) -> String {
    var prompt: String

    if !rewrite.systemPrompt.isEmpty {
      prompt = rewrite.systemPrompt
    } else {
      prompt = defaultImproverPrompt(tone: rewrite.tone)
      if !rewrite.context.isEmpty {
        prompt += "\n\nKontext: \(rewrite.context)"
      }
    }

    if !customTerms.isEmpty {
      prompt +=
        "\n\nWichtig: Diese Eigennamen und Fachbegriffe müssen exakt so geschrieben werden: \(customTerms.joined(separator: ", "))"
    }

    // Memory block is only ever passed when the global master AND the per-mode toggle are on;
    // gating lives at the call site (AppState) so plain Diktat is never affected.
    if let memory, let block = memoryContextBlock(memory) {
      prompt += block
    }

    if let userIdentity, let block = userIdentityBlock(userIdentity) {
      prompt += block
    }

    if let emailMemory, let block = semanticEmailMemoryBlock(emailMemory) {
      prompt += block
    }

    if rewrite.useAutomaticFieldContext,
      let block = automaticContextBlock(automaticContext)
    {
      prompt += block
    }

    if let block = selectionContextBlock(for: rewrite.replyContextMode, selection: selection) {
      prompt += block
    }

    return prompt
  }

  static func userIdentityBlock(_ identity: UserIdentityContext) -> String? {
    let name = identity.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    return """


      [Schreibperspektive]
      Ich schreibe als: \(name)
      Nutze diese Identität, um Pronomen, Absenderperspektive und Signaturbezug korrekt zu verstehen. \
      Wenn der aktuelle Fenster- oder Auswahlkontext E-Mail-Felder wie Von, An, Betreff oder \
      bisherigen Nachrichtentext enthält, leite daraus ab, an wen ich schreibe und wer mir geschrieben \
      hat. Erfinde keine Empfänger, Absender, Zusagen oder Fakten.
      """
  }

  static func semanticEmailMemoryBlock(_ context: EmailSemanticMemoryContext) -> String? {
    guard !context.isEmpty else { return nil }
    let matches = Array(context.matches.prefix(context.level.retrievalLimit))
    guard !matches.isEmpty else { return nil }

    var lines = ["\n\n[Ähnliche frühere E-Mails – nur Hintergrund, nicht abschreiben]"]
    for (index, match) in matches.enumerated() {
      let record = match.record
      lines.append("Beispiel \(index + 1) · Score \(String(format: "%.2f", match.score))")
      if let appName = trimmed(record.appName) {
        lines.append("App: \(appName)")
      }
      if let windowTitle = trimmed(record.windowTitle) {
        lines.append("Kontext: \(windowTitle)")
      }
      lines.append(record.finalText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    lines.append(
      "Nutze diese Beispiele nur, um Ton, wiederkehrende Hintergrunddetails und Schreibweise besser zu treffen. Übernimm keine Fakten, Zusagen, Termine oder Namen, wenn sie in meiner aktuellen Diktat-Nachricht nicht bestätigt werden."
    )
    return lines.joined(separator: "\n")
  }

  // MARK: - Memory context block (Phase 4b)

  /// Renders the structured personal-vocabulary block as a SPELLING hint (not "use these words").
  static func memoryContextBlock(_ memory: MemoryContext) -> String? {
    guard !memory.isEmpty else { return nil }
    var lines = ["\n\n[Persönliches Vokabular – exakt so schreiben]"]
    if !memory.names.isEmpty {
      lines.append("Namen: \(memory.names.joined(separator: ", "))")
    }
    if !memory.terms.isEmpty {
      lines.append("Fachbegriffe: \(memory.terms.joined(separator: ", "))")
    }
    if !memory.foreign.isEmpty {
      lines.append("Fremdwörter: \(memory.foreign.joined(separator: ", "))")
    }
    lines.append(
      "Diese Begriffe sind Schreibweisen-Hinweise: Wenn sie vorkommen, schreibe sie exakt so. Erzwinge sie nicht."
    )
    return lines.joined(separator: "\n")
  }

  static func automaticContextBlock(_ context: AutomaticRewriteContext?) -> String? {
    guard let context, !context.isEmpty else { return nil }
    let trimmed = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var metadata: [String] = []
    if let appName = context.appName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !appName.isEmpty
    {
      metadata.append("App: \(appName)")
    }
    if let windowTitle = context.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
      !windowTitle.isEmpty
    {
      metadata.append("Fenster: \(windowTitle)")
    }

    let metadataLine = metadata.isEmpty ? "" : "\n\(metadata.joined(separator: " · "))"
    return """


      --- Aktueller Arbeitskontext aus dem fokussierten Fenster ---\(metadataLine)
      \(trimmed)
      --- Ende Arbeitskontext ---
      Nutze den obigen Arbeitskontext nur, um die diktierte Nachricht passend fortzusetzen oder \
      darauf zu antworten. Übernimm daraus keine neuen Fakten, Zusagen oder Namen, wenn ich sie in \
      meiner Diktat-Nachricht nicht bestätige.
      """
  }

  // MARK: - Emoji prompt

  static func emojiSystemPrompt(_ rewrite: RewriteConfig, customTerms: [String] = []) -> String {
    let densityInstruction: String
    switch rewrite.emojiDensity {
    case .wenig:
      densityInstruction = "Setze nur vereinzelt Emojis ein, maximal 1-2 pro Absatz."
    case .mittel:
      densityInstruction = "Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze."
    case .viel:
      densityInstruction = "Setze grosszuegig Emojis ein, gerne mehrere pro Satz."
    }

    let customPrompt = rewrite.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    var prompt =
      customPrompt.isEmpty
      ? "Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, aber fuege passende Emojis ein. \(densityInstruction) Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. Gib NUR den Text mit Emojis zurueck, keine Erklaerungen."
      : customPrompt

    if !customTerms.isEmpty {
      prompt +=
        "\n\nWichtig: Diese Eigennamen und Fachbegriffe müssen exakt so geschrieben werden: \(customTerms.joined(separator: ", "))"
    }

    return prompt
  }

  // MARK: - Helpers

  private static func defaultImproverPrompt(tone: TextImprovementSettings.TextTone) -> String {
    var prompt = """
      Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
      - Korrigiere Rechtschreibung und Grammatik
      - Verbessere die Formulierung und den Lesefluss
      - Behalte die urspruengliche Bedeutung bei
      - Gib NUR den verbesserten Text zurueck, keine Erklaerungen
      """
    switch tone {
    case .formal:
      prompt += "\n- Verwende einen formellen, professionellen Ton"
    case .neutral:
      prompt += "\n- Verwende einen neutralen, klaren Ton"
    case .casual:
      prompt += "\n- Verwende einen lockeren, natuerlichen Ton"
    }
    return prompt
  }

  private static func trimmed(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }

  private static func selectionContextBlock(
    for mode: ReplyContextMode,
    selection: SelectionContext?
  ) -> String? {
    guard mode != .off, let selection, !selection.isEmpty else { return nil }

    switch mode {
    case .off:
      return nil
    case .replyUsingContext:
      // Reply may use the selection or, failing that, the surrounding text as context.
      let source =
        selection.selectedText.isEmpty ? selection.surroundingText : selection.selectedText
      let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return replyBlock(trimmed)
    case .editSelection:
      // Editing requires a real selection — never silently rewrite the whole field.
      let trimmed = selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return editBlock(trimmed)
    }
  }

  private static func replyBlock(_ trimmed: String) -> String {
    """


    --- Markierter Text aus der aktuellen App (Kontext) ---
    \(trimmed)
    --- Ende ---
    Der obige Text ist der Kontext, auf den ich mich beziehe. Formuliere meine diktierte \
    Nachricht als passende, in sich geschlossene Antwort darauf. Wiederhole den Originaltext nicht wörtlich.
    """
  }

  private static func editBlock(_ trimmed: String) -> String {
    """


    --- Zu bearbeitender Text ---
    \(trimmed)
    --- Ende ---
    Wende meine diktierten Änderungen auf den obigen Text an und gib NUR die überarbeitete \
    Fassung dieses Textes zurück.
    """
  }

}
