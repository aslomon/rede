import Foundation

// MARK: - Workflow Types

enum WorkflowType: String, CaseIterable, Identifiable, Codable {
  case transcription
  case localTranscription
  case textImprover
  case dampfAblassen
  case emojiText

  var id: String { rawValue }

  static var mainMenuCases: [WorkflowType] {
    allCases.filter { $0 != .localTranscription }
  }

  var displayName: String {
    switch self {
    case .transcription: return "Blitztext"
    case .localTranscription: return "Blitztext Lokal"
    case .textImprover: return "Blitztext+"
    case .dampfAblassen: return "Blitztext $%&!"
    case .emojiText: return "Blitztext :)"
    }
  }

  var icon: String {
    switch self {
    case .transcription: return "mic.fill"
    case .localTranscription: return "lock.shield.fill"
    case .textImprover: return "text.badge.checkmark"
    case .dampfAblassen: return "flame.fill"
    case .emojiText: return "face.smiling"
    }
  }

  var subtitle: String {
    switch self {
    case .transcription: return "Sprache rein. Text raus."
    case .localTranscription: return "Nur lokal. Kein Server."
    case .textImprover: return "Geschrieben sprechen."
    case .dampfAblassen: return "Frust rein. Entspannt raus."
    case .emojiText: return "Text rein. Emojis dazu."
    }
  }

  var hotkeyLabel: String {
    switch self {
    case .transcription: return "fn + Shift"
    case .localTranscription: return "fn + Shift + Ctrl"
    case .textImprover: return "fn + Control"
    case .dampfAblassen: return "fn + Option"
    case .emojiText: return "fn + Cmd"
    }
  }

  var accentColor: String {
    switch self {
    case .transcription: return "blue"
    case .localTranscription: return "green"
    case .textImprover: return "purple"
    case .dampfAblassen: return "orange"
    case .emojiText: return "cyan"
    }
  }
}

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
  case idle
  case running(String)
  case done(String)
  case error(String)

  var isActive: Bool {
    switch self {
    case .idle: return false
    default: return true
    }
  }
}

enum WorkflowLaunchSource: Equatable {
  case manual
  case hotkeyBackground

  var presentsWorkflowPage: Bool {
    switch self {
    case .manual:
      return true
    case .hotkeyBackground:
      return false
    }
  }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

// MARK: - Archive run record (Phase 4)

/// A single completed run, emitted right before `onOutput`. Text-only — never audio.
/// For plain transcription `rawTranscript == finalText`.
struct ArchiveRunRecord: Sendable {
  let mode: WorkflowType
  let rawTranscript: String
  let finalText: String
  let backend: TranscriptionBackend
  let durationSec: Double
  let date: Date

  init(
    mode: WorkflowType,
    rawTranscript: String,
    finalText: String,
    backend: TranscriptionBackend,
    durationSec: Double,
    date: Date = Date()
  ) {
    self.mode = mode
    self.rawTranscript = rawTranscript
    self.finalText = finalText
    self.backend = backend
    self.durationSec = durationSec
    self.date = date
  }
}

/// Invoked once per completed run, right before `onOutput`. Default-nil so disabled == zero I/O.
typealias WorkflowRunHandler = @MainActor (ArchiveRunRecord) -> Void

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
  var type: WorkflowType { get }
  var phase: WorkflowPhase { get set }
  var isRecording: Bool { get }
  /// Live microphone level (0...1) while recording. Drives the menu-bar waveform and the
  /// floating recording pill. All concrete workflows already expose this via their recorder.
  var audioLevel: Float { get }
  var onOutput: WorkflowOutputHandler? { get set }
  var onPhaseChange: WorkflowPhaseChangeHandler? { get set }
  /// Emitted with raw+final+mode right before `onOutput`. Wired ONLY when archiving is enabled.
  var onRun: WorkflowRunHandler? { get set }

  func start()
  func stop()
  func reset()
}

// MARK: - App Settings

struct AppSettings: Codable {
  var hotkeyMode: HotkeyMode = .hold
  var hasSeenOnboarding: Bool = false
  var secureLocalModeEnabled: Bool = false
  var selectedLocalTranscriptionModelName: String = LocalTranscriptionService
    .recommendedFastModelName
  var hasAutoSelectedFastLocalModel: Bool = false
  /// Phase 3: the local rewrite model served by Ollama (e.g. "gemma3"). Used by the `.local`
  /// rewrite backend. Global (like the WhisperKit transcription model), not per-mode.
  var selectedLocalLLMModelName: String = OllamaService.defaultModelName
  /// Per-slot configurable mode settings, keyed by `WorkflowType.rawValue`.
  /// Stored as a String-keyed dictionary so JSONEncoder writes a keyed object (not an array).
  var modes: [String: ModeConfig] = [:]
  var didMigrateToModeConfigs: Bool = false
  var modesSchemaVersion: Int = 1
  /// Phase 4a: persist text-only transcription history. Opt-in, default OFF.
  var archiveEnabled: Bool = false
  /// Phase 4b: inject the confirmed Memory block into rewrite prompts (global master).
  /// Per-mode `RewriteConfig.useMemoryContext` must ALSO be on. Default OFF.
  var memoryContextEnabled: Bool = false
  /// Phase 1 (signing): set true once Accessibility trust was ever observed. Drives the
  /// stale-grant hint: if previously granted but now `AXIsProcessTrusted()` is false (e.g.
  /// after a rebuild changed the CDHash), macOS may still show Blitztext enabled while not
  /// recognizing it. Persisted so the hint survives relaunches.
  var hadAccessibilityGrant: Bool = false

  init(
    hotkeyMode: HotkeyMode = .hold,
    hasSeenOnboarding: Bool = false,
    secureLocalModeEnabled: Bool = false,
    selectedLocalTranscriptionModelName: String = LocalTranscriptionService
      .recommendedFastModelName,
    hasAutoSelectedFastLocalModel: Bool = false,
    selectedLocalLLMModelName: String = OllamaService.defaultModelName,
    archiveEnabled: Bool = false,
    memoryContextEnabled: Bool = false,
    hadAccessibilityGrant: Bool = false
  ) {
    self.hotkeyMode = hotkeyMode
    self.hasSeenOnboarding = hasSeenOnboarding
    self.secureLocalModeEnabled = secureLocalModeEnabled
    self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
    self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
    self.selectedLocalLLMModelName = selectedLocalLLMModelName
    self.archiveEnabled = archiveEnabled
    self.memoryContextEnabled = memoryContextEnabled
    self.hadAccessibilityGrant = hadAccessibilityGrant
  }

  enum CodingKeys: String, CodingKey {
    case hotkeyMode
    case hasSeenOnboarding
    case secureLocalModeEnabled
    case selectedLocalTranscriptionModelName
    case hasAutoSelectedFastLocalModel
    case selectedLocalLLMModelName
    case modes
    case didMigrateToModeConfigs
    case modesSchemaVersion
    case archiveEnabled
    case memoryContextEnabled
    case hadAccessibilityGrant
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
    hasSeenOnboarding =
      try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
    secureLocalModeEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled) ?? false
    selectedLocalTranscriptionModelName =
      try container.decodeIfPresent(
        String.self,
        forKey: .selectedLocalTranscriptionModelName
      ) ?? LocalTranscriptionService.recommendedFastModelName
    hasAutoSelectedFastLocalModel =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .hasAutoSelectedFastLocalModel
      ) ?? false
    selectedLocalLLMModelName =
      try container.decodeIfPresent(
        String.self,
        forKey: .selectedLocalLLMModelName
      ) ?? OllamaService.defaultModelName
    modes = try container.decodeIfPresent([String: ModeConfig].self, forKey: .modes) ?? [:]
    didMigrateToModeConfigs =
      try container.decodeIfPresent(Bool.self, forKey: .didMigrateToModeConfigs) ?? false
    modesSchemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .modesSchemaVersion) ?? 1
    archiveEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .archiveEnabled) ?? false
    memoryContextEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .memoryContextEnabled) ?? false
    hadAccessibilityGrant =
      try container.decodeIfPresent(Bool.self, forKey: .hadAccessibilityGrant) ?? false
  }
}

enum TranscriptionBackend: String, Codable {
  case remote
  case local
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
  var language: String = "de"
}

struct DampfAblassenSettings: Codable {
  var systemPrompt: String =
    "Du erhältst ein emotional gesprochenes Transkript. Erkenne zuerst das eigentliche Ziel, Anliegen und den wahren Frust der Person. Formuliere daraus eine klare, respektvolle und wirksame Nachricht, mit der die Person ihr Ziel eher erreicht. Bewahre relevante Fakten, konkrete Probleme, Grenzen, Erwartungen und die nötige Dringlichkeit. Entferne Beleidigungen, Drohungen, Sarkasmus, Unterstellungen und unnötige Eskalation. Wenn mehrere Vorwürfe genannt werden, verdichte sie auf die entscheidenden Kernpunkte. Der Ton soll ruhig, menschlich, bestimmt und lösungsorientiert sein. Gib NUR die fertige Nachricht zurück."
  var customName: String = ""
}

struct EmojiTextSettings: Codable {
  var emojiDensity: EmojiDensity = .mittel
  var customName: String = ""

  enum EmojiDensity: String, Codable, CaseIterable, Identifiable {
    case wenig
    case mittel
    case viel

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .wenig: return "Wenig"
      case .mittel: return "Mittel"
      case .viel: return "Viel"
      }
    }
  }
}

struct TextImprovementSettings: Codable {
  var systemPrompt: String = ""
  var customTerms: [String] = []
  var context: String = ""
  var tone: TextTone = .neutral
  var customName: String = ""

  enum TextTone: String, Codable, CaseIterable, Identifiable {
    case formal
    case neutral
    case casual

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .formal: return "Formell"
      case .neutral: return "Neutral"
      case .casual: return "Locker"
      }
    }
  }
}
