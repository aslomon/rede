# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Phase 1 – Code-signing & Accessibility**: Robust self-signed code-signing with stable identity support and stale-grant detection
  - **AccessibilityPermissionService**: Enhanced monitoring system with transition-only notifications (no spurious re-fires)
    - `startMonitoring(onChange:)` + `stopMonitoring()`: Low-frequency timer + workspace app-activation listener for grant state changes
    - `requestPermissionPrompt()` & `openSystemSettings()`: Explicit user-driven grant request and system settings navigation
    - Transition detection: only fires `onChange` on actual `AXIsProcessTrusted()` state changes, not every poll cycle
  - **build.sh**: Stable local code-signing with optional ad-hoc fallback
    - `resolve_codesign_identity()`: Detects "Blitztext Local Dev" identity and validates it can actually sign (covers key-access blockers)
    - `sign_app_bundle()`: Dual-mode signing—stable mode (hardened runtime + entitlements, constant CDHash across rebuilds → TCC grants survive) vs. ad-hoc fallback
    - Guides users to optional `scripts/create-dev-cert.sh` for persistent TCC grant survival
  - **AppSettings.hadAccessibilityGrant**: New persistence flag to track if accessibility was ever observed; enables stale-grant UX hints
- **Phase 4 – Archive & Memory**: Text-only archive store with intelligent Memory context system (opt-in, disabled by default)
  - **ArchiveStore**: Persistent storage of run records with raw transcripts for offline indexing
  - **MemoryStore**: Candidate-based memory system with confirmed/denied term curation, category-aware ranking, and injection cap
  - **MemoryCoordinator**: Orchestrates daily maintenance, hash-gated app-launch catch-up, and on-demand recomputation
  - **Memory context injection**: Structured context blocks passed to rewrite workflows (TextImprover, DampfAblassen modes only)
  - **effectiveCustomTerms**: Combined ranking of user custom terms + confirmed memory terms for Whisper hint injection
  - **Memory UI**: Archive view with suggestion scoring, confirmation/denial workflow, and clearance options
- **Mode System**: New configurable text rewriting modes (API-based + Apple Foundation Models) with curated email and prompt defaults
- **ModeConfig.swift**: Core mode model and mode registry with per-mode email templates and prompt settings
- **RewriteModelRegistry.swift**: Real OpenAI model IDs, dynamic `/v1/models` API client for model availability checking
- **RewriteProvider.swift**: Unified provider abstraction supporting OpenAI, Apple Foundation Models, and provider selection context
- **SelectionContextService.swift**: Captures selection context (filename, window title, content type) for intelligent prompt adaptation
- **ModeCardView.swift**: UI component for browsing and selecting rewriting modes with visual mode presentation; added Memory context toggle for rewrite modes
- **DESIGN.md**: Comprehensive architecture and design documentation covering mode system, provider implementations, and UI patterns
- **docs/PLAN-v2.md**: Implementation plan for Blitztext v2 with phased feature roadmap (stable signing, accessibility grants, local LLM, Prompts tab)
- **docs/PLAN-modi-und-features.md**: Detailed planning document for the mode system infrastructure and feature implementation
- **LLMError**: New error cases `modelUnavailable` and `localModelUnavailable` for better error handling and user feedback
- **Recording Pill Overlay**: Floating top-center UI pill for visual recording feedback
  - **RecordingPillController**: Manages pill window lifecycle and positioning
  - **audioLevel** property added to **WorkflowProtocol**: Exposes live microphone level (0...1) for waveform visualization
  - Integrates with **MenuBarStatusController** for dual visual feedback (menu-bar waveform + floating pill)

### Changed

- **WorkflowProtocol.swift**: Extended with AppSettings support and mode management (`modes` property, `updateMode` handling); added `onRun` callback for archive ingestion; added `audioLevel` property for microphone level feedback
- **AppDelegate**: Integrated RecordingPillController for floating recording UI; wired status change callbacks to update pill visibility and state
- **AppState.swift**: Major refactoring to support mode infrastructure and Phase 4 Memory/Archive
  - Added mode state management and migrations
  - Integrated provider factory with backend gating
  - Implemented selection context capture
  - Updated all workflow instantiation to use provider-based approach
  - Integrated ArchiveStore, MemoryStore, and MemoryCoordinator initialization
  - Added Memory maintenance methods: `runMemoryLaunchMaintenanceIfNeeded()`, `recomputeMemory()`
  - Added Memory curation methods: `confirmMemory()`, `denyMemory()`, `unconfirmMemory()`
  - Added Archive/Memory toggle properties with privacy controls
  - Wired archive ingestion callback to workflows (opt-in when archiveEnabled)
  - Threaded `memoryContext` and `effectiveCustomTerms` into all rewrite workflows
  - Code formatting: consistent indentation and import organization
- **LLMService.swift**: Refactored as provider-agnostic prompt builder
  - Removed OpenAI-specific request/response structs (moved to provider implementations)
  - New `rewriteSystemPrompt()` method supporting custom terms and selection context integration
  - Added default rewrite temperature constant (0.3)
  - Preserved system prompt builders for email, prompt, and generic improvement modes
- **DampfAblassenWorkflow.swift**: Migrated from hardcoded provider to dynamic provider selection; threaded memoryContext parameter for archive-aware context injection
- **EmojiTextWorkflow.swift**: Migrated from hardcoded provider to dynamic provider selection
- **TextImprovementWorkflow.swift**: Migrated from hardcoded provider to dynamic provider selection; threaded memoryContext parameter for archive-aware context injection
- **TranscriptionWorkflow.swift**: Updated to use effectiveCustomTerms (combining user custom terms + ranked memory terms) for Whisper hint injection
- **ModeConfig.swift**: Extended with `useMemoryContext` flag per rewrite mode to gate Memory context injection (TextImprover/DampfAblassen only)
- **SettingsContentView.swift**: Added mode management UI with ModeCardView integration; added Archive and Memory toggle controls with privacy/clearance options; code formatting improvements
- **ModeConfig.swift**: Renamed `RewriteBackend.appleIntelligence` → `.local` with user-facing label "Lokal" for clarity; added tolerant decoder to safely migrate legacy settings files that reference the old "appleIntelligence" key
- **DESIGN.md**: Clarified picker guidance to use `.segmented` only for 2–3 short options (with long labels defaulting to Menu-Picker); renamed "Apple-Intelligence-Hinweis" section to "Offline-/Lokal-Hinweis" for terminology consistency
- **AppSupportPaths.swift**: Added paths for archive storage (history.json) and Memory store (memory.json) with 0600 file permissions for privacy

### Fixed

- Provider selection now respects backend configuration and availability
- **Privacy fix**: Transcription now runs locally in secure offline mode using WhisperKit — audio no longer leaves the device
- **Fail-closed**: macOS < 26 with forced offline mode no longer silently falls back to OpenAI — strictly enforces local-only processing
- **Silent downgrade prevented**: Migration no longer forces `secureLocalModeEnabled=false` — user's offline choice is preserved
- **Default names**: Correct fallback names when selection context is unavailable
- **EditSelection guard**: `editSelection` workflow only activates with genuine text selection, not empty selections
- **Reply context path**: Cleaned up reply context path handling in workflow execution
- **Clipboard fallback**: Improved handling of auto-paste fallback mechanism
