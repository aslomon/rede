# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Silence Trimming & Long Dictations**: New opt-in feature to cut long speech pauses from recordings before transcription
  - `SilenceTrimmer`: On-device pause detection and removal (audio never leaves the device)
  - `AppSettings.silenceTrimmingEnabled`: New toggle; default OFF (conservative, avoids clipping quiet word edges)
  - Dramatically shortens audio files (faster/cheaper online uploads) while preserving content fidelity
  - Configured via `AudioRecorder.audioForTranscription()` static method; seamless fallback to original if trimming fails
- **Configurable Dictation Duration Cap**: Replaces hard-coded 180-second limit with user-configurable `AppSettings.maxDictationMinutes`
  - Default 30 minutes (generous, covers typical long-form dictation); synced to `AudioRecorder.maxRecordingDuration` at startup and on settings changes
  - Cap guards against runaway/forgotten recordings, not a feature limit — users can record for hours if needed
  - Existing installs immediately gain long-dictation support without re-configuration
- **Improved Transcription Timeout Handling**: Separate inactivity vs. hard timeout for OpenAI uploads
  - `TranscriptionService.requestTimeout` (120s): Per-request inactivity window; resets while data flows
  - `TranscriptionService.resourceTimeout` (600s): Hard cap on entire transfer (upload + server-side transcription)
  - Enables multi-minute dictations to complete on slower connections without premature truncation at 60s

### Changed

- **AppState Recording Settings Sync**: New `applyRecordingSettings()` method syncs `AudioRecorder` globals from persisted settings
  - Called at launch and on every settings change; recorder reads these values when arming the next recording
  - Ensures duration cap and silence-trimming preferences take effect immediately
- **TranscriptionWorkflow Silence Trimming Integration**: Workflows now run finished audio through `SilenceTrimmer` when enabled
  - `AudioRecorder.audioForTranscription(original:)` returns trimmed or original URL; caller cleans up temp files if different
  - Graceful fallback: trimming failure returns original audio, never costing the user their recording
- **User Identity for Email Context**: New onboarding step (IdentityStepView) to collect user's display name
  - Used in email rewrite prompts to generate responses from the correct perspective
  - Injected as stable vocabulary term to help Whisper recognition
  - Stored locally in user settings
- **Memory Auto-Confirmation**: Recurring domain terms now automatically promote to confirmed vocabulary when they meet frequency thresholds
  - Names and foreign words auto-confirm after 2 document appearances
  - Generic terms require 3 document appearances to avoid normal noun contamination
  - Common word denylist (200+ German + 200+ English words) prevents noise terms from auto-learning
- **MemoryCommonWords**: Comprehensive denylist of high-frequency language words to prevent normal vocabulary from contaminating learned terms
- **Selection Context Enhancements**: Improved detection and capture of document context (filename, window title, content type) for intelligent prompt adaptation
- **LLMService Vocabulary Injection**: New support for stable user-term injection in prompt generation
- **Fallback Pill Card (Copy-Only Mode)**: When automatic paste fails due to missing accessibility permissions or target app focus issues, the recording pill now transitions to a copy-only state with:
  - Expanded scrollable card displaying the recorded text
  - Copy button for easy clipboard transfer
  - Cmd+V hint text to guide manual pasting
  - Prevents dictation text from being silently stuck in clipboard

### Changed

- **Memory System Semantics**: Terminology shifted from "confirmed" to "learned" terms to reflect auto-promotion behavior
  - Learned terms remain active for transcription/rewrite even when Memory master toggle is off
  - Removing a learned term now denylists it to prevent immediate re-learning
  - Recognition/vocabulary lists always show learned terms (they're stable vocabulary, not ephemeral suggestions)
- **AppState Vocabulary Terms**:
  - User's display name is now automatically included in `effectiveCustomTerms` and `effectiveRewriteTerms`
  - Memory terms are always injected (no longer gated by `memoryContextEnabled` toggle)
  - New property `recognizeTerms` provides unified "richtig erkennen & schreiben" list combining manual terms and learned vocabulary
- **Vocabulary Settings UI**: Redesigned for clarity with explicit source tags (manual vs. learned)
  - Learned terms show auto-promotion logic and denylist behavior
  - Denylisting prevents terms from auto-learning again
- **Paste Reliability**: `attemptPasteTrusted` now uses `.activateIgnoringOtherApps` to reliably activate target applications
  - Fixes silent paste failures on recent macOS where background .accessory app's plain `activate()` is unreliable
  - Ensures valid pastes don't degrade to copy-only fallback unnecessarily
- **Recording Pill Centering**: Fixed pill positioning and sizing issues
  - Removed 4-edge host pin constraint that caused incorrect width calculation
  - Now uses `intrinsicContentSize` with leading/top pins for proper centering
  - Orders panel before positioning to ensure `panel.screen` is available on first show
- **Memory Recomputation**: Now triggers auto-confirmation of recurring candidates when recompute runs

### Fixed

- **MenuBarStyle Glass Modifiers**: Consolidated duplicate `BlitztextSurface`, `PillGlassModifier`, and `CardGlassModifier` definitions into unified LiquidGlass.swift module to eliminate code duplication and simplify macOS version targeting
- **AppState Code Formatting**: Improved indentation consistency and multi-line parameter alignment across workflow instantiation and helper methods
- **Accessibility Fallback Flow**: No longer just flashes red when accessibility permission is missing; now gracefully transitions to copy-only pill with guiding text
- **Recording Pill Visibility**: Resolved NSHostingView sizing collapse where pill was invisible due to missing constraints
- **Memory Term Deduplication**: Fixed handling of lemma-based deduplication to prevent already-learned terms from reappearing in suggestions

### Added (Previous Phases)

- **Local Model Manager & Window**: Standalone UI for Ollama model discovery, download, and lifecycle management
  - **LocalModelManager**: Orchestrates Ollama connectivity, installed model inventory, and download/delete operations
  - **LocalModelsWindowController**: Resizable standalone window (separate from popover) accessible via "Modelle verwalten & laden …" button
  - **System Info Card**: Displays user's hardware (chip, RAM, free storage) with intelligent model recommendations based on available memory
  - **Model Catalog**: Browsable library of 30+ curated models (gemma3, qwen3, llama3.2, llama3.1, phi4, mistral, deepseek-r1, 1B–30B variants) with:
    - Download size per model, estimated RAM footprint
    - Suitability badges (Passt locker / Knapp / Zu groß) based on system memory
    - Live download progress (% per layer) with cancel button
    - Installed model deletion with verification
  - **Freetext Model Input**: Support for arbitrary Ollama tags (e.g., `llama3.1:70b`) beyond curated catalog
  - **Ollama Connectivity**: Honest status messaging and "Ollama öffnen" button when Ollama is offline
  - **OllamaService Expansion**:
    - `pull(tag, onProgress:)`: Stream-based model downloads with task cancellation support
    - `delete(tag)`: Model deletion endpoint
    - `installedModelsDetailed()`: Fetch installed models with on-disk sizes and parameter/quantization metadata
    - Long-lived `transferSession` (6h timeout) for downloads and deletes separate from status polling
    - `InstalledModel` struct with `sizeBytes`, `parameterSize`, `quantization` for UI display
    - `PullProgress` struct for streaming progress updates
    - `OllamaTransferError` for pull/delete-specific error handling
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

- **RecordingPillView**: Complete visual redesign for minimalist elegance
  - Removed "Aufnahme" text label entirely for cleaner interface
  - **Pulsing accent dot** replaces static indicator: gentle breathing scale+opacity animation (1.1s cycle, ±25% scale, ±30% opacity)
  - **Center-mirrored waveform** (PillWaveformView): 22 thin bars rendered on Canvas, mirrored horizontally from center axis with edge-fade and per-mode accent color for live audio feedback
  - Improved hover affordances: asymmetric insertion/removal transitions (scale 0.92 for waveform, 0.88 for buttons), refined button styling (hairline-ring borders, adjusted opacity)
  - Enhanced color refinement: affordance button tint changed from `.secondary` to `Color.primary.opacity(0.55)` for better visual hierarchy
- **RecordingPillController**: Fixed NSHostingView sizing issue where pill was invisible due to zero-size collapse
  - Changed from `translatesAutoresizingMaskIntoConstraints = false` (had no constraints, causing collapse) to `sizingOptions = [.minSize, .intrinsicContentSize]`
  - AppKit now respects SwiftUI's intrinsic content size for proper layout
  - Added screen fallback (`NSScreen.main ?? NSScreen.screens.first`) for edge-case multi-screen scenarios
  - Added comprehensive logging via `pillLogger` for debugging panel visibility and frame issues
- **AppState.swift**:
  - Added `localModelManager` property to back the standalone "Lokale Modelle" window
  - Added `.openLocalModelsWindow` notification name for communicating window open requests
- **BlitztextMacApp.swift**:
  - Instantiated `localModelsWindowController` in AppDelegate to manage the model manager window
  - Added notification observer for `.openLocalModelsWindow` to show the model manager window and close popover
- **ModeCardView.swift**:
  - Added "Modelle verwalten & laden …" button in `LocalLLMModelPicker` that posts `.openLocalModelsWindow` notification
  - Button uses blue accent color and subtle button style for consistent UI presentation
- **WorkflowProtocol.swift**: Extended with AppSettings support and mode management (`modes` property, `updateMode` handling); added `onRun` callback for archive ingestion; added `audioLevel` property for microphone level feedback
- **AppDelegate**: Integrated RecordingPillController for floating recording UI; wired status change callbacks to update pill visibility and state
- **AppState.swift** (earlier phase): Major refactoring to support mode infrastructure and Phase 4 Memory/Archive
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
