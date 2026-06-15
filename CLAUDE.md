> **Herkunft:** Dieses Repository ist der eigenstaendige Spin-off "rede" des Open-Source-Projekts
> Blitztext (MIT, (c) Blitztext contributors). Interne Typ-/Verzeichnisnamen behalten bewusst das
> Blitztext-Praefix, damit Upstream-Merges guenstig bleiben. Nutzersichtbares Branding ist "rede".

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Blitztext is a **native macOS menu bar app** (Swift 5.10, SwiftUI + AppKit), not a web app. It is a local-first dictation, transcription, rewrite, and local-AI workflow tool. There is no hosted backend, account system, sync layer, or telemetry. Do not apply Next.js/Supabase/web conventions here.

`agent.md` is the detailed contributor guide (style, privacy rules, common change patterns, hazards) and `DESIGN.md` is the mandatory design system. **Read `agent.md` before changing logic and `DESIGN.md` before any UI work.** This file is the quick orientation; those two are the source of truth. `AGENTS.md` is a shorter quick-reference covering the same ground (structure, build commands, style, commit/PR conventions) — keep it consistent with `agent.md` when either changes.

## Build, test, run

All scripts are non-interactive. Requires full Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
./build.sh --debug          # debug build
./build.sh --release        # release build (default)
./build.sh --install --run  # build, copy to /Applications, launch
./test.sh                   # run all unit tests (pinned to arm64)
```

Key facts:

- **The Xcode project is generated from `BlitztextMac/project.yml`.** `build.sh`/`test.sh` run `xcodegen generate` first. Manual `.xcodeproj` edits are NOT durable — change `project.yml` instead. After adding/moving Swift files, the generator must re-include them (sources are folder-based: `App`, `Features`, `Services`, `Views`, `Resources`, `Tests`).
- `build.sh` produces a **universal binary** (`arm64 x86_64`) via `clean build` and verifies it with `lipo`.
- `test.sh` pins tests to **arm64 only** (`ARCHS=arm64`) because WhisperKit/ArgmaxOSS ships an arm64-only test-time binary. Don't remove this pin.
- Signing: `build.sh` uses a stable local identity ("Blitztext Local Dev") if installed via `scripts/create-dev-cert.sh`, else falls back to ad-hoc. Stable signing keeps the CDHash constant so Accessibility (TCC) grants survive rebuilds.

### Running a single test

`test.sh` runs everything. To run one test class or method, invoke `xcodebuild` directly with `-only-testing` (regenerate the project first if files changed):

```bash
cd BlitztextMac && xcodegen generate
xcodebuild test \
  -project BlitztextMac.xcodeproj -scheme BlitztextMac -configuration Debug \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath ../.derivedData-tests \
  -only-testing:BlitztextMacTests/ModeConfigDefaultsTests
# append /testMethodName to target a single method
```

Run `./test.sh` after logic changes; run `./build.sh --debug` after structural, UI, resource, signing, or project-config changes.

## Architecture big picture

Layering is **App → Features → Services**, enforced by convention (see `agent.md` "Architecture Rules"):

- **`App/`** — lifecycle and orchestration. `AppState.swift` is the large central glue; `*WindowController` / `*Controller` types own the menu bar, recording pill, onboarding, archive, and local-models windows. Prefer extracting tested helpers over growing `AppState`.
- **`Features/`** — SwiftUI surfaces: `Workflows/`, `MenuBar/`, `Onboarding/`, `Settings/`, `Shared/`. Business rules must not live inside SwiftUI body builders.
- **`Services/`** — reusable domain behavior: recording, transcription, rewrite providers, hotkeys, storage, permissions, context capture, memory.
- **`Views/`** — reusable visual components (waveform, pill).
- **`Tests/`** — XCTest target `BlitztextMacTests`, focused on pure logic, Codable defaults/migrations, prompts, and decision helpers.

### Workflow model (load-bearing invariant)

There are five fixed workflow slots defined by `WorkflowType`: `transcription`, `localTranscription`, `textImprover`, `dampfAblassen`, `emojiText`. Each maps to a concrete workflow class in `Features/Workflows/`. User-visible labels, hotkeys, model choices, and enrichment are configurable via **`ModeConfig`**, but the slot→class mapping is an invariant — don't break it without a deliberate, tested migration.

### Rewrite pipeline

Prompt construction is provider-agnostic in **`LLMService`**; network transport lives in provider types. Selection flows through `RewriteConfig` → `RewriteBackend` → `RewriteProvider` (`Services/Providers/RewriteProvider.swift`) → `OpenAIRewriteProvider` / `LlamaCppRewriteProvider`, with `RewriteModelRegistry` for model metadata. Keep prompt assembly out of the transport types.

### Two AI backends, kept separate

- **Online**: OpenAI Audio Transcriptions + Chat Completions, called directly with the user's own key (stored only in Keychain via `KeychainService`). 25 MB transcription upload limit — preserve the early-failure path.
- **Local**: WhisperKit/CoreML for transcription (`LocalTranscriptionService`, `LocalModelManager`) and a bundled **llama.cpp** server on `127.0.0.1` (a free local port chosen at launch, managed by `LlamaCppRuntimeService`) for rewrite + embeddings (`LlamaCppRewriteProvider`, `LlamaCppEmbeddingProvider`; models via `LlamaCppModelCatalog` / `LlamaCppModelStore` / `LlamaCppDownloadService`, transport via `LlamaCppServerClient`). Local transcription readiness and local rewrite readiness are **separate concerns** — do not merge their checks.

### Memory & context (all opt-in, capped)

Semantic email memory (`EmailSemanticMemoryStore`, `EmailMemoryRetriever`, embeddings via `LlamaCppEmbeddingProvider`), vocabulary/term learning (`MemoryStore`, `MemoryCoordinator`, `FuzzyTermCorrector`), improvement mining (`ImprovementMiner`/`ImprovementLog`), and automatic field/selection context (`SelectionContextService`, `PasteContextAXReader`). These read or store user content — keep them opt-in, retention-aware, and clearly described in copy.

## Critical project-specific rules

These come from `agent.md`/`DESIGN.md` — the highest-leverage ones to internalize:

- **Privacy honesty**: never claim a workflow is local/offline unless the code proves no audio/text leaves the Mac. Keep OpenAI calls direct (no hidden proxy/telemetry). Keep local llama.cpp traffic on `localhost`. Use `URLSessionConfiguration.ephemeral`. Delete temp audio after processing/cancellation. Preserve copy-only fallback when auto-paste fails.
- **Codable backward compatibility**: new persisted settings need safe missing-key defaults plus round-trip + missing-key tests, so old settings files still decode.
- **No App Sandbox**: the app runs unsandboxed; entitlements live in `Resources/BlitztextMac.entitlements` (audio input + network client only). Do not broaden entitlements casually.
- **UI**: in-app text is German (informal, concise); code/comments/commits/docs are English. Menu bar popover is 410 pt wide. Reuse existing styles (`PopoverActionButtonStyle`, `SectionLabel`, `BlitzStatusPill`, `MenuBarTokens`, …) and preserve mode accent colors. Don't add brand colors/gradients without updating `DESIGN.md`.
- **TCC fragility**: rebuilding/re-signing can break Accessibility permission. Preserve the stable local-signing behavior in `build.sh`.
- Use `Logger` from `os` for diagnostics — no `print` in production code. Surface user-facing errors as concise German `LocalizedError` messages.
