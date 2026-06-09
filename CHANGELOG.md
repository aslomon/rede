# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Local Model Download Progress Reporting**: Fixed frozen-looking model downloads by implementing real progress updates
  - **Download Delegate Implementation**: Replaced `URLSession.download(from:)` (which reports no progress) with custom `URLSessionDownloadDelegate` that streams incremental progress via `didWriteData` callbacks
  - **Progress UI**: Now shows "Lädt … X.X / 1.3 GB" with accurate progress fraction (throttled to ~8 MB steps to avoid excessive updates)
  - **Ephemeral Session**: Uses ephemeral `URLSession` for download task management, properly bridging completion to async/await via `CheckedContinuation`
  - **Verified Checksum**: Validated downloaded GGUF files against HuggingFace catalog checksums to ensure integrity before installation

### Changed

- **Onboarding Window Title Bar Modernization**: Redesigned title bar for contemporary macOS appearance
  - **Transparent Full-Size Content View**: Added `.fullSizeContentView` and transparent titlebar so glass surface extends to the top window edge
  - **Floating Traffic Lights**: Traffic lights now float over content instead of sitting in an opaque title band above each step
  - **Movable by Window Background**: Enabled window dragging from the background area; adjusted left sidebar padding to accommodate floating controls
  - **Visual Consistency**: Matches modern macOS design language seen in apps like Safari and Preview, eliminating the opaque title bar that interrupted the glass surface
- **Settings Popover Density & Layout**: Optimized for more content without scrolling
  - **Increased Minimum Height**: Settings page now enforces `minHeight: 600pt` (vs. 410pt main page width) to display more controls before scrolling
  - **Engine Bar Relocation**: Removed engine/model selection footer from main popover page; now lives exclusively in Settings → Modelle tab
- **Processing Mode Selector**: Clear visual choice between Online (OpenAI) and Local (Secure) processing
  - **Mode Toggle**: New segmented picker at top of Modelle settings: "Online · OpenAI" vs. "Lokal · Sicher" driving `secureLocalModeEnabled` flag
  - **Visual Dimming**: Non-selected mode section (Online or Local) now dims to 0.4 opacity, making active choice obvious at a glance
  - **Auto-Install on Switch**: Selecting "Lokal · Sicher" now automatically installs the selected local model (Whisper + Ollama) if not yet installed
  - **Configurable Offline Setup**: Users can still configure OpenAI key (or vice versa) ahead of time despite dimming, for smooth mode switching
- **Menu Bar Headers Redesign**: Complete visual overhaul across Main, Settings, and Workflow headers
  - **Brand Identity**: Integrated Blitztext brand logo (BrandMark component) into Main and Settings headers for consistent visual anchor
  - **Main Header**: Reorganized from multi-line to single clean row: `[Logo] Blitztext [Bereit Status] … [⚙]` with inline status pill (removed separate status line)
  - **Settings Header**: New format: `[← Back] [Logo] Settings [Right Actions]` with brand mark for consistency
  - **Workflow Header**: Preserved existing mode-icon design; logo integration optional for future refinement
  - **Simplified Layout**: Removed header divider (no visual separation); transparent background using standard surface color
- **Window Headers with BrandMark**: Added Blitztext brand logo (18pt BrandMark) to three window headers
  - **Transcription Archive Header**: Logo now displays before "Transkriptions-Archiv" title for visual consistency
  - **Local Models Header**: Logo now displays before "Lokale Modelle" title for visual consistency
  - **Onboarding Header**: Logo now displays before "Blitztext einrichten" title for visual consistency
  - **BrandMark Accessibility**: Made BrandMark component public (module-level) for reuse across window headers (previously private to MenuBarView)
- **Local Whisper Model Loading**: Enhanced user feedback during model initialization
  - **Model Loading State**: Added `localModelPreparing` flag to surface slow first-load initialization (ANE compilation on large models can take minutes)
  - **Model Switching Behavior**: When user explicitly switches Whisper models, new model now preloads immediately with visible status instead of blocking on next dictation
  - **Status Visibility**: Prevents user confusion about hang/error when large models take time to compile and load into memory
- **Improvement Detection Section**: Updated privacy disclosure text from "Lokal protokolliert (0600)" to "Lokal protokolliert (nur du)" for clarity
- **Paste Context Section**: Updated privacy disclosure text from "Lokal protokolliert (0600)" to "Lokal protokolliert (nur du)" for consistency
- **Improvements List**: Removed clear button from bottom of improvements list (clutter reduction)
- **Onboarding Wizard Layout Redesign**: Complete restructuring from horizontal top-header + content layout to left-rail + content design
  - **Brand Rail (Left)**: New persistent left sidebar (196pt width) displaying Blitztext logo, full step list with icons, current step highlighting (accent color + background), completed steps marked with checkmark, and "Schritt X von Y" counter at bottom
  - **Step List Visual Hierarchy**: Current step emphasizes name in semibold with accent color background; completed steps show green checkmark; upcoming steps appear faded; all steps navigable via click
  - **Content Area (Right)**: Removed top header entirely; content now full-width with consistent glass surface throughout; footer buttons remain at bottom
  - **Visual Cohesion**: Wizard now reads as one uniform surface rather than a page with separate header; unified glass backdrop across entire window
  - **Window Sizing**: Adjusted minimum width to 680pt (from 600pt) to accommodate left rail; height reduced slightly to 520pt (from 540pt) for better screen fit
  - **Animation**: Retained asymmetric push transitions for step content; updated spring animation for smoother step navigation
- **Local Models Settings Reorganization**: Restructured hardware-aware model management and recommendation flow
  - **Hardware Specs First**: New "Dieser Mac" section moved to top with system capabilities card (RAM, GPU, architecture) — shown directly, not collapsed
  - **Catalog Filtering**: "Verfügbare Modelle" section now filters out models too large to run on device (tooLarge fit rating) preventing download of unrunnable models
  - **Ollama Recommendation Card**: New blue-accented recommendation banner in Models tab shows hardware-recommended model with direct download button when no local LLM is selected yet
  - **Duplicate Size Removal**: Removed redundant size display in LocalModelRowView (size already shown in hardware specs card)
- **Model Activation Button Clarity**: Changed all model "Nutzen" (activate) buttons from primary to secondary button style
  - **Visual Distinction**: Secondary style clearly differentiates activation from primary "Laden" (download) action
  - **Affected Areas**: LocalModelRowView, LocalModelsView (Whisper and Ollama sections), WhisperModelsSection
  - **UX Clarity**: Users no longer confuse downloading a model with activating an already-installed model

### Added

- **BrandMark Component**: New reusable SVG logo renderer for menu bar headers; loads Blitztext brand icon from bundled resource with template rendering for foreground tinting
- **LocalTranscriptionService Model Selection Helper**: New `selectionAfterDeleting()` static method to intelligently choose the next model after deletion, preserving current selection if still available or falling back to recommended/remaining models
- **LocalTranscriptionService Model Deletion**: New `deleteModel()` method to safely remove installed Whisper models from disk and unload from in-memory pipeline
- **Liquid Glass Design System (macOS 26+)**: Centralized Glass-effect component library with native `.glassEffect` support and intelligent fallbacks
  - **glassRowBackground Static Fallback**: Simplified hover behavior to calm, static accent tint on all macOS versions (removed overly animated interactive morph that read as gimmicky on dense utility lists)
  - **LiquidGlass.swift**: Core module providing unified glass modifiers and container views (`.liquidGlassCard()`, `.liquidGlassCapsule()`, `.liquidGlassTintedCard()`, `.liquidGlassKeycap()`, `.glassRowBackground()`, `GlassEffectContainerView`)
  - **GlassActionButtonStyle & GlassProminentButtonStyle**: Consistent button styles across glass surfaces
  - **Fallback strategy**: Native glass effects on macOS 26+; transparent `.regularMaterial` + `MenuBarTokens` fills on macOS 14–25 (no degradation, smooth appearance on all supported versions)
- **DESIGN.md**: Comprehensive Liquid Glass design documentation with visual guidelines, component catalog, and implementation patterns

### Changed

- **Popover Engine Panel**: Redesigned with collapsed `BlitzStatusPill` footer (status → action → details); workflow rows now use morphing glass-hover effects; status unified as pill throughout
- **Prompts & Modes UI**:
  - `ModeCardView` upgraded with glass-card background and visual mode accent stripe
  - Hotkey recorder buttons now fixed-position with improved visibility
  - Single unified edit entry point per mode
  - **Modi-Karten UI-Cleanup**: Removed colored accent bar, changed mode name from uppercase to regular styling with larger font weight (more prominent as section title), removed redundant "Aktiv" status pill (toggle already indicates active state), fixed control alignment in disclosure group (now all controls line up flush left)
- **Models Settings**:
  - Removed redundant top status (status now unified in section header pills)
  - Explanatory text moved behind interactive `InfoDisclosure` components
  - Delete action redesigned as `.danger` icon with accessibility labels
- **Vocabulary Settings**: Reordered to show memory-learned terms first; "Jetzt analysieren" as primary action; improvement nudge as tinted banner
- **Archive & System Settings**:
  - Privacy disclosure text moved behind `InfoDisclosure`
  - Action bar now shows disabled states instead of hiding actions
  - Permission button hierarchy corrected per platform conventions
  - Permission blockers now listed first
  - **Archive Window**: Fixed ScrollView width so card shadows display without lateral clipping (cards now visually flush with window edges)
- **Onboarding Wizard**:
  - Glass-backdrop introduction step
  - Progress indicator changed from 8-capsule strip to segmented counter with step label
  - Fixed Escape key conflict with step navigation
  - Directional push transitions between steps
- **Recording Pill Simplification**:
  - Reverted to original minimalist design (single pill state without GlassEffectContainer morphing)
  - Removed namespace-based morphing between pill/card/variant states
  - Kept visual simplicity: hover-driven affordance animations (scale, opacity) without complex state transitions
  - Error state continues to use red tint for visual feedback
- **build.sh**: Added `ENABLE_DEBUG_DYLIB=NO` to prevent Xcode 26 signature mismatch on debug builds (affects `--debug` flag only; Release/Signing unaffected)

### Fixed

- **MenuBarStyle Glass Modifiers**: Eliminated duplicate `BlitztextSurface`, `PillGlassModifier`, and `CardGlassModifier` definitions by consolidating into unified LiquidGlass.swift module
- **glassRowBackground Hover Behavior**: Disabled interactive morphing Liquid Glass hover effect (macOS 26+) in favor of calm, static accent tint on all macOS versions; interactive morphing was overly animated for dense utility lists and conflicted with nested glass in popovers
- **Grammar Fix**: Corrected "1 Einträge" → "1 Eintrag" singular form in email semantic memory status label
- **ModeCardView Advanced Controls Alignment**: Fixed DisclosureGroup wrapping that left-aligned wide controls but centered narrow ones; now all controls line up flush left via explicit leading VStack
- **LocalLLMModelPicker Duplicate Status Pill**: Removed redundant "Aktiv" pill in inline status row (model name only); the active state is already shown by the header status pill, eliminating visual duplication

### Added (Previous Phases)

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
