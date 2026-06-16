import Foundation

// MARK: - Mode building blocks

/// What a slot actually DOES, independent of its user-facing name.
/// Stored but not user-editable in this phase (the active-view downcasts in
/// MenuBarView depend on a slot keeping its workflow class).
enum ModeKind: String, Codable, Sendable {
  case transcribeOnly
  case transcribeThenRewrite
  case transcribeThenEmoji
}

enum ModeTemplate: String, CaseIterable, Identifiable, Sendable {
  case freeText
  case email
  case prompt
  case social

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .freeText: return "Freitext"
    case .email: return "E-Mail"
    case .prompt: return "Prompt"
    case .social: return "Social Media"
    }
  }

  var icon: String {
    switch self {
    case .freeText: return "mic.fill"
    case .email: return "envelope.fill"
    case .prompt: return "terminal.fill"
    case .social: return "bubble.left.and.bubble.right.fill"
    }
  }

  var slot: WorkflowType {
    switch self {
    case .freeText: return .transcription
    case .email: return .textImprover
    case .prompt: return .dampfAblassen
    case .social: return .emojiText
    }
  }

  func makeMode(id: ModeConfig.ID) -> ModeConfig {
    var mode = ModeConfig.default(for: slot)
    mode.modeID = id
    mode.userName = displayName
    return mode
  }
}

/// Where the rewrite step runs.
enum RewriteBackend: String, Codable, Sendable, CaseIterable, Identifiable {
  case openai
  case local

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .openai: return "online (OpenAI)"
    case .local: return "lokal"
    }
  }

  /// Tolerant decoder mapping that keeps legacy on-disk settings parseable.
  /// Old files persisted the raw value "appleIntelligence" for the local backend.
  static func from(rawValue raw: String) -> RewriteBackend {
    if let backend = RewriteBackend(rawValue: raw) { return backend }
    switch raw {
    case "appleIntelligence": return .local
    default: return .openai
    }
  }
}

/// How a mode incorporates the text the user has selected in the frontmost app.
enum ReplyContextMode: String, Codable, Sendable, CaseIterable, Identifiable {
  case off
  case replyUsingContext
  case editSelection

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .off: return "aus"
    case .replyUsingContext: return "als kontext (antwort)"
    case .editSelection: return "auswahl bearbeiten"
    }
  }
}

enum SemanticEmailEnrichmentLevel: String, Codable, Sendable, CaseIterable, Identifiable {
  case light
  case medium
  case strong

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .light: return "wenig"
    case .medium: return "mittel"
    case .strong: return "viel"
    }
  }

  var retrievalLimit: Int {
    switch self {
    case .light: return 1
    case .medium: return 2
    case .strong: return 4
    }
  }

  var minimumScore: Double {
    switch self {
    case .light: return 0.78
    case .medium: return 0.68
    case .strong: return 0.58
    }
  }
}

/// Everything that controls the optional rewrite step of a mode.
struct RewriteConfig: Codable, Sendable {
  var systemPrompt: String = ""
  var rewriteBackend: RewriteBackend = .openai
  var modelID: String = RewriteModelRegistry.defaultModelID
  var tone: TextImprovementSettings.TextTone = .neutral
  var context: String = ""
  var emojiDensity: EmojiTextSettings.EmojiDensity = .mittel
  var replyContextMode: ReplyContextMode = .off
  /// When true, the current focused window is read at recording start and injected into the rewrite
  /// prompt as transient working context. Curated rewrite modes enable this by default; users can
  /// disable it per mode.
  var useAutomaticFieldContext: Bool = false
  /// When true (and the global master is on), the confirmed Memory block is rendered into this
  /// mode's rewrite system prompt. Curated rewrite modes enable this by default.
  var useMemoryContext: Bool = false
  var useSemanticEmailMemory: Bool = false
  var semanticEmailEnrichmentLevel: SemanticEmailEnrichmentLevel = .medium
  var showTwoVariants: Bool = false

  init(
    systemPrompt: String = "",
    rewriteBackend: RewriteBackend = .openai,
    modelID: String = RewriteModelRegistry.defaultModelID,
    tone: TextImprovementSettings.TextTone = .neutral,
    context: String = "",
    emojiDensity: EmojiTextSettings.EmojiDensity = .mittel,
    replyContextMode: ReplyContextMode = .off,
    useAutomaticFieldContext: Bool = false,
    useMemoryContext: Bool = false,
    useSemanticEmailMemory: Bool = false,
    semanticEmailEnrichmentLevel: SemanticEmailEnrichmentLevel = .medium,
    showTwoVariants: Bool = false
  ) {
    self.systemPrompt = systemPrompt
    self.rewriteBackend = rewriteBackend
    self.modelID = modelID
    self.tone = tone
    self.context = context
    self.emojiDensity = emojiDensity
    self.replyContextMode = replyContextMode
    self.useAutomaticFieldContext = useAutomaticFieldContext
    self.useMemoryContext = useMemoryContext
    self.useSemanticEmailMemory = useSemanticEmailMemory
    self.semanticEmailEnrichmentLevel = semanticEmailEnrichmentLevel
    self.showTwoVariants = showTwoVariants
  }

  enum CodingKeys: String, CodingKey {
    case systemPrompt, rewriteBackend, modelID, tone, context, emojiDensity, replyContextMode
    case useAutomaticFieldContext, useMemoryContext
    case useSemanticEmailMemory, semanticEmailEnrichmentLevel
    case showTwoVariants
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
    // Decode the raw string and map tolerantly so legacy "appleIntelligence" files
    // (the former on-device case) still parse onto the renamed `.local` backend.
    if let rawBackend = try c.decodeIfPresent(String.self, forKey: .rewriteBackend) {
      rewriteBackend = RewriteBackend.from(rawValue: rawBackend)
    } else {
      rewriteBackend = .openai
    }
    modelID =
      try c.decodeIfPresent(String.self, forKey: .modelID) ?? RewriteModelRegistry.defaultModelID
    tone = try c.decodeIfPresent(TextImprovementSettings.TextTone.self, forKey: .tone) ?? .neutral
    context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
    emojiDensity =
      try c.decodeIfPresent(EmojiTextSettings.EmojiDensity.self, forKey: .emojiDensity) ?? .mittel
    replyContextMode =
      try c.decodeIfPresent(ReplyContextMode.self, forKey: .replyContextMode) ?? .off
    useAutomaticFieldContext =
      try c.decodeIfPresent(Bool.self, forKey: .useAutomaticFieldContext) ?? false
    useMemoryContext =
      try c.decodeIfPresent(Bool.self, forKey: .useMemoryContext) ?? false
    useSemanticEmailMemory =
      try c.decodeIfPresent(Bool.self, forKey: .useSemanticEmailMemory) ?? false
    semanticEmailEnrichmentLevel =
      try c.decodeIfPresent(
        SemanticEmailEnrichmentLevel.self,
        forKey: .semanticEmailEnrichmentLevel
      ) ?? .medium
    showTwoVariants =
      try c.decodeIfPresent(Bool.self, forKey: .showTwoVariants) ?? false
  }
}

// MARK: - Per-slot configuration

/// A configurable, renamable mode layered over the fixed `WorkflowType` slot.
struct ModeConfig: Codable, Sendable, Identifiable {
  /// Stable user-mode identity. Legacy slot configs may omit this on disk; in that case `id`
  /// falls back to the slot raw value so existing settings keep working byte-for-byte.
  var modeID: String?
  var slot: WorkflowType
  var id: String {
    if let modeID {
      let trimmed = modeID.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return slot.rawValue
  }
  var userName: String = ""
  var isEnabled: Bool = true
  var kind: ModeKind
  var rewrite: RewriteConfig = RewriteConfig()

  init(
    modeID: String? = nil, slot: WorkflowType, userName: String = "", isEnabled: Bool = true, kind: ModeKind,
    rewrite: RewriteConfig = RewriteConfig()
  ) {
    self.modeID = modeID
    self.slot = slot
    self.userName = userName
    self.isEnabled = isEnabled
    self.kind = kind
    self.rewrite = rewrite
  }

  enum CodingKeys: String, CodingKey {
    case modeID, slot, userName, isEnabled, kind, rewrite
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    modeID = try c.decodeIfPresent(String.self, forKey: .modeID)
    let decodedSlot = try c.decodeIfPresent(WorkflowType.self, forKey: .slot) ?? .transcription
    slot = decodedSlot
    userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
    isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    kind =
      try c.decodeIfPresent(ModeKind.self, forKey: .kind)
      ?? ModeConfig.defaultKind(for: decodedSlot)
    rewrite =
      try c.decodeIfPresent(RewriteConfig.self, forKey: .rewrite)
      ?? ModeConfig.defaultRewrite(for: decodedSlot)
  }

  // MARK: - Defaults

  static func defaultKind(for slot: WorkflowType) -> ModeKind {
    switch slot {
    case .transcription, .localTranscription: return .transcribeOnly
    case .textImprover, .dampfAblassen: return .transcribeThenRewrite
    case .emojiText: return .transcribeThenEmoji
    }
  }

  /// User-facing default names for the repurposed slots.
  static func defaultUserName(for slot: WorkflowType) -> String {
    switch slot {
    case .transcription: return "Diktat"
    case .localTranscription: return "Diktat (lokal)"
    case .textImprover: return "E-Mail"
    case .dampfAblassen: return "Prompt"
    case .emojiText: return "Social"
    }
  }

  static func defaultRewrite(for slot: WorkflowType) -> RewriteConfig {
    switch slot {
    case .textImprover:
      return RewriteConfig(
        systemPrompt: ModeDefaults.emailSystemPrompt,
        modelID: RewriteModelRegistry.strongModelID,
        useAutomaticFieldContext: true,
        useMemoryContext: true,
        useSemanticEmailMemory: true)
    case .dampfAblassen:
      return RewriteConfig(
        systemPrompt: ModeDefaults.promptCraftSystemPrompt,
        modelID: RewriteModelRegistry.strongModelID,
        useAutomaticFieldContext: true,
        useMemoryContext: true)
    case .emojiText:
      return RewriteConfig(modelID: RewriteModelRegistry.fastModelID)
    case .transcription, .localTranscription:
      return RewriteConfig()
    }
  }

  static func `default`(for slot: WorkflowType) -> ModeConfig {
    ModeConfig(
      slot: slot,
      userName: defaultUserName(for: slot),
      isEnabled: true,
      kind: defaultKind(for: slot),
      rewrite: defaultRewrite(for: slot)
    )
  }

  static func duplicate(
    _ source: ModeConfig,
    newID: String,
    userName: String
  ) -> ModeConfig {
    var duplicate = source
    duplicate.modeID = newID
    duplicate.userName = userName
    duplicate.isEnabled = true
    return duplicate
  }

  // MARK: - Progressive disclosure

  /// True when any "advanced" rewrite setting deviates from this slot's curated default:
  /// a custom system prompt, or a tone / context / reply-context / memory choice that differs.
  /// Drives the "angepasst" dot shown next to the collapsed "Erweitert" toggle in `ModeCardView`.
  /// Pure (no SwiftUI / AppState), so it is directly unit-testable.
  var isAdvancedNonDefault: Bool {
    let defaults = ModeConfig.defaultRewrite(for: slot)
    // "angepasst" = a genuinely custom prompt (non-empty AND different from the curated default —
    // an empty/cleared prompt reverts to tone/context, so it's NOT a customization), or any
    // tone/context/reply/memory deviation from the slot defaults.
    let promptIsCustom =
      !rewrite.systemPrompt.isEmpty && rewrite.systemPrompt != defaults.systemPrompt
    return promptIsCustom
      || rewrite.tone != defaults.tone
      || rewrite.context != defaults.context
      || rewrite.replyContextMode != defaults.replyContextMode
      || rewrite.useAutomaticFieldContext != defaults.useAutomaticFieldContext
      || rewrite.useMemoryContext != defaults.useMemoryContext
      || rewrite.useSemanticEmailMemory != defaults.useSemanticEmailMemory
      || rewrite.semanticEmailEnrichmentLevel != defaults.semanticEmailEnrichmentLevel
      || rewrite.showTwoVariants != defaults.showTwoVariants
  }
}

// MARK: - Curated default prompts

enum ModeDefaults {
  static let emailSystemPrompt = """
    # Role and objective

    You are an email-writing assistant. You receive a raw, often disorganized spoken transcript in which the user roughly says what they want to write to someone. You turn it into a finished, clearly structured email. Your output is the email itself: the exact text the user will send.

    # Input

    - A transcript produced by speech-to-text (Whisper) from the user's dictation. Expect it to be unordered and to contain filler words, false starts, self-corrections, repetitions, and transcription errors (including misspelled names).
    - Optionally, additional context may be provided alongside the transcript, such as a previous email or the prior conversation thread.

    # Guiding principle: fidelity over embellishment

    The transcript is the single source of truth for the message. Preserve, without exception, every stated fact, name, number, date, deadline, and the actual concern or request. Never drop, weaken, or "tidy away" content, and never invent anything the user did not say. When in doubt, keep it.

    # Instructions embedded in the transcript

    The transcript may contain explicit directives about how to write the email, as opposed to content for the email. Follow these directives; do not render them as email text. For example, if the user says something like "this does not belong in the email, but please keep it in mind while writing," treat it as an instruction to consider, not as a sentence to include. Distinguish carefully between what the user wants written and what the user is telling you to do.

    # Using provided context

    If a previous email or conversation thread is provided:
    - Use it to inform the reply and address the relevant points from it.
    - Always write from the user's perspective as the sender — you are composing the user's message, never the other party's. Do not adopt or echo the counterpart's viewpoint as if it were the user's.
    - Use the context only to ground the reply; do not import facts or commitments from it that the user did not confirm.

    # What you may and must clean up

    - Reorganize freely for clarity and logical flow.
    - Remove disfluencies: filler ("äh", "sozusagen", "im Endeffekt"), repetitions, and abandoned starts. For self-corrections, keep only the user's final intent.
    - Fix grammar and sentence structure.
    - Correct obviously mis-transcribed names and terms only where the intended form is clear; never introduce names or details the user did not mention.

    # Email structure

    Produce a complete, ready-to-send email:
    1. A fitting salutation.
    2. A logically organized body in flowing prose, broken into short paragraphs.
    3. A polite closing.

    # Tone and register

    - Write naturally, professionally, and warmly, without overdoing formulaic pleasantries (no excessive "Floskeln").
    - Match the level of formality (Sie/Du) to what the transcript and any provided context imply about the relationship; when unclear, default to the formal "Sie".

    # Missing elements

    - If neither the transcript nor the context provides a salutation, choose a suitable neutral one.
    - If no closing is provided, choose a suitable neutral closing.

    # Subject line

    Do not write a subject line, unless the user explicitly dictates one. If they do, include it.

    # Language

    Write the email in the same language that was detected during transcription. Do not translate the user's message into another language.

    # Output discipline

    Return ONLY the finished email. Do not add any preamble, explanation, meta-commentary, or notes. Do not add a subject line unless one was explicitly dictated. Do not wrap the email in quotes or in code fences. Do not announce what you are about to do. Your entire response is the email and nothing else.
    """

  static let promptCraftSystemPrompt = """
    # Role and objective

    You transform a raw, often disorganized spoken transcript — in which the user describes a programming or work task — into a single, polished, ready-to-use prompt for an AI coding agent such as Claude Code or Codex. Your output is the prompt itself: the exact text the user will hand to that agent.

    # Core logic: recognize → improve, otherwise just structure

    - Where you can identify concrete intent, requirements, or details, sharpen them and present them clearly.
    - Where you cannot identify anything beyond loose talk, simply clean up and structure the language as it stands.
    - In neither case do you add task content. Structuring better is always allowed; inventing is never allowed.

    # Input

    A transcript produced by speech-to-text (Whisper) from the user's dictation. It may be unordered and may contain filler words, false starts, self-corrections, repetitions, and transcription errors (including misspelled technical terms). It may also be very short, high-level, or refer to context you cannot see.

    # Guiding principle: fidelity over embellishment (highest priority)

    The transcript is the single source of truth for *what* the task is. Add nothing to it.

    - Preserve, without exception, every substantive element the user states: requirements, intent, file names, paths, function names, identifiers, libraries, numbers, constraints, and implied priorities. If the user says something like "it is not in paths X, Y or in the scripts," keep that exactly.
    - Never invent task content. Do not fabricate file names, paths, component or function names, library or framework versions, dimensions, CSS classes, technical rules, constraints, or any other specific the user did not say. If a detail is not in the transcript, it does not appear in the prompt.
    - Inventing a plausible-sounding but unstated task is the single worst failure you can make. When information is missing, leave it missing.

    # You have no access to the user's code or environment

    You only ever know what the user dictated. You cannot see the codebase, files, scripts, or session state, and you must not act as if you can. Never describe or assume the contents of files you have not been shown.

    # Length and scope proportionality

    Match the output's length and specificity to the input.

    - A short, high-level transcript produces a short, high-level prompt. A two-sentence dictation must not become a long, detailed specification.
    - If the user was vague, the resulting prompt stays vague — that is correct, not a deficiency to "fix" by adding detail.
    - Do not pad. No invented sections, no filler requirements.

    # Missing or referenced-but-unavailable context

    The transcript may reference context you do not have — existing code, prior work, current file locations, session state. Never fabricate it. Instead:

    - Faithfully relay the user's instruction and intent as stated.
    - For specifics the user references but does not provide (paths, current state, what was already done), insert an explicit placeholder such as `[hier ergänzen: …]`, or instruct the receiving agent to determine them first.
    - Do not invent a concrete task to make the prompt look complete.

    # Light execution methodology (optional, brief)

    You may weave in light, generic process guidance — but only as a short clause or half-sentence, never as an elaborate multi-step process block. It is most appropriate when the user mentions changing or modifying something that already exists. Typical, sufficient additions are, for example:
    - "Verschaffe dir zuerst den Kontext der zugehörigen Dateien."
    - "Führe am Ende ein kurzes Review durch."

    Add at most a clause like these, keep each to one short sentence, and omit them entirely for vague or trivial transcripts. Such a clause must never introduce task specifics the user did not state.

    # What you may and must clean up

    - Reorganize freely for clarity and logical flow.
    - Remove disfluencies: filler ("äh", "sozusagen", "im Endeffekt"), repetitions, and abandoned starts. For self-corrections, keep only the user's final intent.
    - Fix grammar and sentence structure.
    - Convert spoken technical terms into their correct written form (e.g., "Kodex" → Codex, "Klod Code" → Claude Code, "Next JS" → Next.js, "Type Script" → TypeScript, "Supabase", "Tailwind"). Only correct terms the user actually said; never introduce technologies they did not mention.

    # Roles and framing

    Add a brief role or framing line only if the transcript clearly implies one. Do not invent an elaborate persona or a tech stack the user did not mention.

    # Output structure

    Use this order, but include only the sections the transcript actually supports and omit any that would be empty or speculative:
    1. A short task description (1–3 sentences) stating the goal.
    2. Concrete requirements as a bulleted list, preserving all stated details, names, and constraints.
    3. Context and constraints, if any were given.
    4. A short methodology clause (e.g., gather related context first, review at the end), only if warranted — woven in briefly, not as a multi-step block.

    # Language

    Write the prompt in the same language that was detected during transcription. Do not translate.

    # Output discipline

    Return ONLY the finished prompt. No preamble, no explanation, no meta-commentary, no greeting or sign-off, no quotes, no code fences. Do not announce what you are about to do. Your entire response is the prompt and nothing else.
    """

  /// Previous curated defaults, kept ONLY so the one-time prompt-refresh migration can recognize a
  /// mode still on the old text and bump it to the new prompt above (a custom prompt is left as-is).
  /// The first English prompt-craft default (before the recognize→improve rewrite), so a mode already
  /// migrated to it also gets refreshed.
  static let legacyPromptCraftSystemPromptV2 = """
    # Role and objective

    You transform a raw, often disorganized spoken transcript — in which the user describes a programming or work task — into a single, polished, ready-to-use prompt for an AI coding agent such as Claude Code or Codex. Your output is the prompt itself: the exact text the user will hand to that agent.

    # Input

    A transcript produced by speech-to-text (Whisper) from the user's dictation. Expect it to be unordered and to contain filler words, false starts, self-corrections, repetitions, and transcription errors (including misspelled technical terms).

    # Guiding principle: fidelity over embellishment

    The transcript is the single source of truth for what the task is. Preserve, without exception, every substantive element: requirements, intent, file names, function names, paths, identifiers, libraries, frameworks, numbers, constraints, edge cases, and any priority order the user implies. Never drop, weaken, or tidy away content, and never invent task content, requirements, or assumptions the user did not express. When in doubt, keep it.

    # What you may and must clean up

    - Reorganize freely for clarity and logical flow.
    - Remove disfluencies: filler ("äh", "sozusagen", "im Endeffekt"), repetitions, and abandoned starts. For self-corrections, keep only the user's final intent.
    - Fix grammar and sentence structure.
    - Convert spoken technical terms into their correct written form (e.g., "Kodex" → Codex, "Klod Code" → Claude Code, "Next JS" → Next.js, "Type Script" → TypeScript, "Supabase", "Tailwind"). Only correct terms the user actually said; never introduce technologies they did not mention.

    # Distinguish task content from execution methodology

    Two kinds of additions exist, governed by different rules:

    1. Task content (requirements, features, constraints, deliverables): NEVER add anything not present in the transcript.
    2. Execution methodology (how a capable agent should approach the work): you MAY add standard agentic best practices when they fit, because these improve outcomes without changing what is being asked. Keep them clearly in the realm of process guidance.

    Methodology you may add when it suits a coding task:
    - Instruct the agent to gather full context before coding — read the relevant and connected files and understand existing patterns and conventions.
    - Encourage deep analysis of non-trivial subproblems, optionally delegating to subagents.
    - Suggest orchestration: decompose the task into ordered subtasks and coordinate them.
    - Ask the agent to verify its work afterward — self-review against the stated requirements and run tests/linters/build where relevant.

    Do not attach all of these to every prompt. A trivial one-line change needs no orchestration, subagents, or review. Match the scaffolding to the task's complexity as implied by the transcript.

    # Adaptive intensity

    Calibrate how much you transform. If the transcript is already clear, do little more than restructure and clean up the language. If it is messy or complex, impose structure, group related points, and add appropriate methodology — still without inventing content.

    # Roles and framing

    Add a brief role or framing line only when it genuinely helps the agent (e.g., "You are working in an existing Next.js/TypeScript codebase"). Derive any such framing from the transcript; do not fabricate context that was not implied.

    # Output structure

    Produce the prompt in this order:
    1. A short task description (1–3 sentences) stating the goal.
    2. Concrete requirements as a bulleted list, preserving all details, names, and constraints.
    3. Context and constraints, if any.
    4. Process/methodology instructions for the agent, if appropriate to the task.

    # Language

    Write the prompt in the same language as the transcript (default to German for a German transcript). Use precise, correct technical terminology rather than colloquial paraphrases.

    # Output discipline

    Return ONLY the finished prompt. Do not add any preamble, explanation, meta-commentary, greeting, or sign-off. Do not wrap the prompt in quotes or in code fences. Do not announce what you are about to do. Your entire response is the prompt and nothing else.
    """
  static let legacyEmailSystemPrompt = """
    Du bist ein Schreibassistent für E-Mails. Du erhältst ein gesprochenes, ungeordnetes Transkript, in \
    dem ich grob sage, was ich jemandem schreiben will. Formuliere daraus eine fertige, klar \
    strukturierte E-Mail auf Deutsch: passende Anrede, logisch gegliederter Fließtext in kurzen \
    Absätzen, höflicher Abschluss. Behalte alle genannten Fakten, Namen, Zahlen, Termine und das \
    eigentliche Anliegen exakt bei und erfinde nichts dazu. Schreibe natürlich, professionell und \
    freundlich, ohne Floskeln zu übertreiben. Fehlt eine Anrede oder Grußformel, wähle eine passende \
    neutrale. Gib NUR die fertige E-Mail zurück, ohne Erklärungen und ohne Betreffzeile, außer ich \
    diktiere ausdrücklich einen Betreff.
    """

  static let legacyPromptCraftSystemPrompt = """
    Du erhältst ein gesprochenes, ungeordnetes Transkript, in dem ich eine Programmier- oder \
    Arbeitsaufgabe für einen KI-Coding-Agenten (Claude Code oder Codex) beschreibe. Formuliere daraus \
    einen klaren, gut strukturierten Prompt auf Deutsch. Behalte ausnahmslos alle inhaltlichen Details, \
    Anforderungen, Datei- und Funktionsnamen, Randbedingungen und meine Absicht bei – kürze nichts \
    Inhaltliches weg und räume nicht übereifrig auf. Strukturiere den Prompt logisch: kurze \
    Aufgabenbeschreibung, dann konkrete Anforderungen als Aufzählung, dann ggf. Kontext oder \
    Einschränkungen. Nutze präzise, korrekte Fachbegriffe statt umgangssprachlicher Umschreibungen, \
    aber erfinde keine Anforderungen dazu, die ich nicht gesagt habe. Wandle gesprochene Code- oder \
    Technik-Begriffe in ihre korrekte Schreibweise um. Gib NUR den fertigen Prompt zurück, ohne \
    Vorbemerkung oder Erklärung.
    """
}
