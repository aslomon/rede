> **About:** rede is a standalone, local-first macOS menu-bar app. It began as a fork but has been
> heavily rewritten and renamed — the codebase no longer carries any legacy prefix. Origin & MIT
> license attribution live in `README.md` and `LICENSE`.

# Agent Guide

This repository is a native macOS menu bar app, not a web app. Treat the local code and docs as the source of truth, and do not apply generic Next.js or backend conventions unless the project is explicitly expanded in that direction.

## Project Snapshot

- Product: rede, a local-first macOS dictation, transcription, rewrite, and local AI workflow app.
- Platform: macOS 14+, Swift 5.10, SwiftUI with AppKit integration.
- Project generation: XcodeGen via `RedeMac/project.yml`.
- Main target: `RedeMac`, built as `rede.app`.
- Tests: XCTest target `RedeMacTests`.
- External Swift package: `argmax-oss-swift` / WhisperKit, pinned in `project.yml`.
- Remote services: OpenAI audio transcription and chat completions, called directly from the app with the user's own API key.
- Local services: WhisperKit/CoreML model folders for transcription and the bundled llama.cpp runtime (a `localhost` server, started as a subprocess) for local rewriting and e-mail-memory embeddings.
- There is no hosted backend, account system, sync layer, telemetry service, or bundled model package.

## Repository Layout

```text
RedeMac/
  App/          App lifecycle, popover/window controllers, AppState orchestration
  Features/     SwiftUI features: workflows, menu bar UI, onboarding, settings
  Services/     Recording, transcription, rewrite providers, storage, permissions, context
  Views/        Reusable visual views such as waveform and recording pill views
  Resources/    Info.plist, entitlements, app icons, asset catalogs
  Tests/        XCTest coverage for pure logic, stores, model state, prompts, and workflows
docs/           Setup, privacy, local models, planning, and release notes
build.sh        Non-interactive local build/sign/install/run script
test.sh         Non-interactive XCTest runner pinned to arm64 for WhisperKit tests
DESIGN.md       Mandatory design system for all UI work
```

## Communication And Documentation

- Speak German informally with the user.
- Keep code, code comments, commit messages, and repository docs in English.
- Be direct and act autonomously. Ask only when the repo cannot answer a blocking question.
- Explain privacy-impacting changes explicitly.
- Do not claim a workflow is local/offline unless the implementation proves that no audio/text leaves the Mac.

## Required First Steps

Before changing code:

1. Check the worktree with `git status --short`.
2. Read the relevant files before editing; do not infer architecture from filenames alone.
3. For UI/design work, read `DESIGN.md` first and update it when making new durable visual decisions.
4. Check whether related tests already exist in `RedeMac/Tests`.
5. Preserve unrelated user changes. Never reset, checkout, or delete unowned work as a shortcut.

Use `rg` / `rg --files` for local search.

## Build And Test Commands

Use only non-interactive commands.

```bash
./build.sh --debug
./build.sh --release
./build.sh --install --run
./test.sh
```

Important details:

- `build.sh` generates the Xcode project with XcodeGen when available.
- `build.sh` creates a universal app (`arm64 x86_64`) and signs it locally.
- `test.sh` runs `xcodebuild test` with `ARCHS=arm64` because WhisperKit's test-time binary dependency is arm64-only.
- If adding or moving Swift files, ensure XcodeGen still includes them through `project.yml`, then regenerate/build.
- Do not use interactive Xcode-only fixes as the sole solution; keep the command-line build working.

## Architecture Rules

- Keep `AppState` as orchestration glue, not a dumping ground for new domain logic.
- Put reusable domain behavior in `Services/`.
- Put workflow-specific behavior in `Features/Workflows/`.
- Put UI in `Features/...` or `Views/`; do not hide business rules inside SwiftUI body builders.
- Keep prompt construction provider-agnostic in `LLMService`.
- Keep network transport inside provider/service types such as `OpenAIRewriteProvider`, `LlamaCppRewriteProvider`, `LlamaCppServerClient`, and the transcription services.
- Prefer small pure functions for parsing, prompt assembly, persistence transforms, and decision logic so they can be tested without AppKit permissions.
- Maintain `@MainActor` boundaries for UI, AppKit, pasteboard, accessibility, and observable state.
- Move expensive file, model, and text processing work off the main actor with structured concurrency.
- Avoid new dependencies unless they materially reduce complexity and are documented in `project.yml`.

## Swift Style

- Use Swift strictness rather than loose dynamic patterns.
- Prefer `struct`, `enum`, protocols, and value semantics for pure domain concepts.
- Prefer `final class` for reference types that are not intended to be subclassed.
- Prefer named, descriptive APIs over abbreviations.
- Avoid force unwraps except for static constants that are guaranteed valid and already follow local style.
- Avoid broad `catch` blocks that erase useful error information.
- Surface user-facing errors as concise German `LocalizedError` messages.
- Use `Logger` from `os` for diagnostics; do not add `print` or `console`-style debug output to production code.
- Keep comments rare and useful. Use them for non-obvious macOS/TCC, concurrency, privacy, or fallback behavior.

## Privacy And Security Rules

This app handles audio, transcripts, clipboard contents, API keys, selected text, and accessibility context. Treat those as sensitive.

- Never commit API keys, transcripts, recordings, model files, or private local data.
- Store API keys only in macOS Keychain through `KeychainService`.
- Keep OpenAI calls direct and explicit; do not add hidden proxying, telemetry, analytics, or hosted services.
- Use `URLSessionConfiguration.ephemeral` for network clients unless there is a clear reason not to.
- Keep local llama.cpp traffic on `localhost`; do not redirect local rewrite text to remote services.
- Temporary audio must be deleted after processing or cancellation.
- Clipboard behavior must remain honest: if auto-paste fails, preserve copy-only fallback UX.
- Accessibility context and automatic field context must remain opt-in, capped, and clearly described.
- Archive, memory, and improvement mining features must stay opt-in and retention-aware.
- The app currently runs without the macOS App Sandbox; do not broaden entitlements casually.

## UI And Design Rules

Follow `DESIGN.md` exactly.

- UI text inside the app is German, informal, and concise.
- The menu bar popover is 410 pt wide.
- Use native SwiftUI/AppKit controls first: `Picker`, `Toggle`, `TextField`, `TextEditor`, `GroupBox`-style groups, and standard button styles already present in the repo.
- Reuse project styles such as `PopoverActionButtonStyle`, `PopoverIconButtonStyle`, `SectionLabel`, `BlitzStatusPill`, `InfoDisclosure`, and `MenuBarTokens`.
- Use SF Symbols for icons.
- Preserve the mode accent colors:
  - transcription: blue
  - local transcription: green
  - text improver: purple
  - calmer/frustration mode: orange
  - emoji mode: cyan
- Keep settings dense, calm, and status-first: state, primary action, optional details.
- Do not stack glass effects. Popover/floating pill can use glass; inner settings surfaces should stay native and restrained.
- Do not add new brand colors, decorative illustrations, or generic AI-looking gradients without updating `DESIGN.md`.

## Workflow Model

The fixed workflow slots are defined by `WorkflowType`:

- `transcription`
- `localTranscription`
- `textImprover`
- `dampfAblassen`
- `emojiText`

Mode labels and behavior are configurable through `ModeConfig`, but slots still map to concrete workflow classes. Preserve this invariant unless doing a deliberate migration with tests.

Rewrite behavior is controlled by:

- `RewriteConfig`
- `RewriteBackend`
- `RewriteProvider`
- `OpenAIRewriteProvider`
- `LlamaCppRewriteProvider` (+ `LlamaCppRuntimeService`, `LlamaCppModelCatalog`)
- `LLMService`
- `RewriteModelRegistry`

When adding a workflow or mode setting, update Codable defaults and migration behavior so old settings files still decode safely.

## Persistence And Local Data

- Use existing app support path helpers in `AppSupportPaths`.
- Use `SecureFileWriter` or existing store patterns for sensitive local JSON.
- Keep Codable changes backward compatible with missing-key defaults.
- Add tests for new persisted fields, migrations, retention behavior, and old JSON decoding.
- Do not write user data into the repository, logs, screenshots, or build artifacts.

## Testing Expectations

Add or update focused XCTest coverage for:

- Prompt construction and rewrite backend selection.
- Codable defaults and migration behavior.
- Privacy-sensitive toggles and opt-in gates.
- Local/remote fallback messages.
- Dictionary, memory, archive, context, and improvement-mining logic.
- Pure formatting and UI decision helpers.
- Error descriptions users depend on.

Prefer tests around pure functions and injected dependencies. Avoid tests that require real microphone, real Accessibility permission, real OpenAI credentials, or a live local model server unless the task explicitly calls for integration testing.

Run `./test.sh` after logic changes. Run `./build.sh --debug` after structural, UI, resource, signing, or project configuration changes.

## Common Change Patterns

When adding a setting:

1. Add the field with a safe default.
2. Update custom Codable decoding if old files may lack the key.
3. Add round-trip and missing-key tests.
4. Wire UI through existing settings primitives.
5. Make privacy impact explicit in copy if the setting reads, stores, or sends user content.

When adding a model option:

1. Update the relevant catalog or registry.
2. Keep installed and suggested models visually distinct.
3. Do not mark a model as available until the local service confirms it.
4. Add tests for normalization, labels, and fallback behavior.

When changing paste or Accessibility behavior:

1. Read `AppState`, `RecordingPillController`, `PasteboardSnapshot`, `SelectionContextService`, and `PasteContextAXReader`.
2. Preserve manual paste fallback.
3. Preserve clipboard restoration semantics.
4. Test pure decision logic and manually verify the macOS permission flow when possible.

When changing prompts:

1. Keep prompt text in English unless the prompt is intentionally user-facing German copy.
2. Preserve fidelity rules: never invent facts, commitments, names, dates, or intent.
3. Add tests for important prompt blocks and option gates.
4. Avoid hidden behavior changes in unrelated modes.

## Project-Specific Hazards

- `AppState.swift` is large and central. Prefer extracting tested helpers instead of expanding it further.
- Some docs are older than the implementation. If docs conflict with code, verify behavior in code and update docs when relevant.
- Remote transcription has a 25 MB upload limit; preserve the early failure path.
- Secure local transcription and local rewriting are separate concerns. Do not merge their readiness checks accidentally.
- TCC permissions can break after rebuilding/signing. Preserve stable local signing behavior in `build.sh`.
- The generated `.xcodeproj` is derived from `project.yml`; do not treat manual Xcode project edits as durable.
- App icon and menu bar icon rules are documented in `DESIGN.md`; do not redesign them casually.

## Done Criteria

A change is done when:

- It matches the current macOS SwiftUI architecture.
- It preserves privacy, TCC, clipboard, and local/remote honesty.
- Relevant tests were added or updated.
- `./test.sh` passes for logic changes.
- `./build.sh --debug` passes for app, UI, resource, project, or signing changes.
- Docs are updated when user-facing behavior, setup, privacy, or design rules change.
- The final response states what changed and exactly what verification ran.
