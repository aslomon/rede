# Sprint Plan: Embedded llama.cpp Local LLM Runtime

## Sprint Objective

Replace the current Ollama-only local rewrite path with a runtime-neutral local LLM architecture and introduce llama.cpp via a bundled `llama-server` helper process. The migration must preserve existing Ollama behavior until llama.cpp is production-ready, keep OpenAI workflows untouched, and finish with a full verification suite that covers correctness, packaging, failure modes, security posture, and future API stability.

## Strategic Decision

Use a bundled **`llama-server` helper process** as the first llama.cpp implementation.

Reasons:

- The existing app already speaks HTTP through `RewriteProvider`.
- A helper process avoids Swift/C++ ABI risk and in-process memory lifecycle complexity.
- `llama-server` exposes OpenAI-compatible endpoints, matching the current provider shape.
- Packaging a replaceable helper is easier to pin, sign, test, and upgrade than embedding a static library first.
- Ollama can remain as a fallback runtime while rede-local llama.cpp becomes the default path.

Do not start with MLX or direct `libllama` bindings. MLX can become a later Apple-Silicon optimization path; direct bindings can be reconsidered after the process-based runtime proves product value.

Primary references:

- llama.cpp: `https://github.com/ggml-org/llama.cpp`
- llama-server docs: `https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md`
- llama-server API changelog: `https://github.com/ggml-org/llama.cpp/issues/9291`
- Apple bundle placement: `https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle`
- Apple code signing: `https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac`
- Apple notarization: `https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution`

## Current App Interface Map

### Stable Extension Points

- `RedeMac/Services/Providers/RewriteProvider.swift`
  - Keep `RewriteProvider`.
  - Keep `RewriteOutcome`.
  - Add `LlamaCppRewriteProvider`.
- `RedeMac/App/AppState.swift`
  - Current routing point: `rewriteProvider(for:)`.
  - Current readiness gate: `rewriteBackendReady(for:)`.
- `RedeMac/Features/Workflows/*Workflow.swift`
  - Workflows already accept `any RewriteProvider`.
  - No rewrite workflow rewrite should be required.
- `RedeMac/Services/LLMService.swift`
  - Prompt-building remains provider-neutral.

### Ollama-Specific Areas To Abstract

- `RedeMac/Services/LocalModelManager.swift`
  - Currently an Ollama manager despite generic name.
- `RedeMac/Services/OllamaService.swift`
  - Tags, pull, delete, installed models.
- `RedeMac/Services/OllamaInstallerService.swift`
  - External Ollama installation/start.
- `RedeMac/Services/OllamaModelCatalog.swift`
  - Ollama tags, not GGUF URLs.
- `RedeMac/Services/SystemCapabilities.swift`
  - Recommendations currently tied to `OllamaModelCatalog.Model`.
- `RedeMac/Features/Workflows/WorkflowProtocol.swift`
  - `AppSettings.selectedLocalLLMModelName` stores only an Ollama tag.
- `RedeMac/Features/Workflows/ModeConfig.swift`
  - `RewriteBackend.local` exists, but no local runtime choice.
- UI:
  - `LocalModelsView.swift`
  - `LocalModelRowView.swift`
  - `LocalLLMModelPicker.swift`
  - `ModelsSettingsView.swift`
  - `ModelsStepView.swift`
  - `ModeCardView.swift`
- Tests:
  - `LocalModelStateTests.swift`
  - `OllamaModelManagementTests.swift`
  - `OllamaInstallerTests.swift`
  - `RewriteBackendDecodeTests.swift`
  - `AppSettingsCodableTests.swift`

## Team / Subagent Tracks

### Track A: Runtime Architecture

Ownership:

- `RedeMac/Services/LocalLLMRuntime.swift`
- `RedeMac/Features/Workflows/WorkflowProtocol.swift`
- `RedeMac/Tests/LocalLLMRuntimeTests.swift`
- `RedeMac/Tests/AppSettingsCodableTests.swift`

Responsibilities:

- Define runtime-neutral local LLM data types.
- Add settings migration from old Ollama-only string.
- Preserve existing user settings.

### Track B: Ollama Adapter

Ownership:

- `RedeMac/Services/LocalModelManager.swift`
- `RedeMac/Services/OllamaService.swift`
- `RedeMac/Services/OllamaModelCatalog.swift`
- `RedeMac/Tests/LocalModelStateTests.swift`
- `RedeMac/Tests/OllamaModelManagementTests.swift`

Responsibilities:

- Keep Ollama working through runtime-neutral abstractions.
- Ensure old tests still pass.
- Avoid behavior changes during the abstraction phase.

### Track C: llama.cpp Runtime / Server

Ownership:

- `RedeMac/Services/LlamaCppRuntimeService.swift`
- `RedeMac/Services/LlamaCppServerClient.swift`
- `RedeMac/Tests/LlamaCppRuntimeTests.swift`
- `RedeMac/Tests/LlamaCppServerClientTests.swift`

Responsibilities:

- Manage `llama-server` process lifecycle.
- Bind to `127.0.0.1` only.
- Use a session API key.
- Poll `/health`.
- Decode `/v1/chat/completions`.

### Track D: GGUF Model Management

Ownership:

- `RedeMac/Services/LlamaCppModelCatalog.swift`
- `RedeMac/Services/LlamaCppModelStore.swift`
- `RedeMac/Services/LlamaCppDownloadService.swift`
- `RedeMac/Services/AppSupportPaths.swift`
- `RedeMac/Tests/LlamaCppModelManagementTests.swift`
- `RedeMac/Tests/LlamaCppDownloadServiceTests.swift`

Responsibilities:

- Model catalog with checksums and license metadata.
- Store GGUF files under Application Support.
- Download to `.partial`, validate, then atomically install.
- Ensure partial/corrupt files are never shown as installed.

### Track E: Provider Routing

Ownership:

- `RedeMac/Services/Providers/RewriteProvider.swift`
- `RedeMac/App/AppState.swift`
- `RedeMac/Tests/LlamaCppRewriteProviderTests.swift`
- `RedeMac/Tests/RewriteBackendDecodeTests.swift`
- `RedeMac/Tests/ArchiveReuseTests.swift`

Responsibilities:

- Add `LlamaCppRewriteProvider`.
- Route local rewrites by selected local runtime.
- Preserve OpenAI behavior.
- Preserve archive rerun behavior.

### Track F: UI / UX

Ownership:

- `RedeMac/Features/Settings/LocalModelsView.swift`
- `RedeMac/Features/Settings/LocalModelRowView.swift`
- `RedeMac/Features/Settings/LocalLLMModelPicker.swift`
- `RedeMac/Features/Settings/ModelsSettingsView.swift`
- `RedeMac/Features/Onboarding/Steps/ModelsStepView.swift`
- `RedeMac/Features/Settings/ModeCardView.swift`
- `DESIGN.md`

Responsibilities:

- Change user-facing model language from Ollama-only to runtime-neutral local LLM language.
- Keep Ollama as fallback/advanced runtime.
- Show truth-based states only: installed, loading, starting, ready, missing, failed.
- Update design docs if UI patterns change.

### Track G: Packaging / Release

Ownership:

- `build.sh`
- `RedeMac/project.yml`
- `scripts/`
- `RedeMac/Resources/RedeMac.entitlements`

Responsibilities:

- Pin llama.cpp release/build.
- Build or stage `llama-server`.
- Sign helper before app.
- Verify architecture strategy.
- Add release verification commands.

### Track H: Verification / Code Review

Ownership:

- Test additions across all tracks.
- Review findings.
- Final verification run.

Responsibilities:

- Run tests after each phase.
- Run code-review after each phase.
- Convert findings into fix tasks before next phase starts.
- Maintain QA checklist and release gates.

## Sprint Structure

### Sprint 0: Architecture Lock And Baseline

Goal: freeze the migration approach and confirm the current app baseline.

Tasks:

- Confirm this worktree branch: `codex/llamacpp-runtime`.
- Keep `main` untouched during spike work.
- Record current baseline:
  - `./test.sh`
  - `./build.sh --release`
  - `git status --short --branch`
- Pin initial llama.cpp integration approach:
  - preferred: bundled `llama-server`
  - fallback: external developer-provided `llama-server` path for early spike
  - not in scope: MLX, direct `libllama`, static library
- Freeze current existing behavior:
  - OpenAI rewrite works.
  - Ollama guided install works.
  - Local WhisperKit transcription works.
  - Archive rerun works.

Acceptance criteria:

- Baseline tests and release build pass or known unrelated failures are documented.
- `docs/PLAN-llamacpp-runtime.md` and this sprint plan exist.
- No runtime code has changed yet.

Review gate:

- Architecture review only.
- Confirm no unnecessary code changes.

### Sprint 1: Runtime-Neutral Local LLM Settings

Goal: introduce durable settings and types without changing runtime behavior.

Tasks:

- Add `LocalLLMRuntimeKind`.
  - `.llamaCpp`
  - `.ollama`
- Add `LocalLLMSelection`.
  - runtime
  - model id
  - display name
  - model path or tag
- Add `LocalLLMInstalledModel`.
- Add `LocalLLMModelCatalogEntry`.
- Add `LocalLLMRuntimeStatus`.
  - unavailable
  - installing
  - downloading
  - starting
  - loadingModel
  - ready
  - failed
- Extend `AppSettings`:
  - keep `selectedLocalLLMModelName` for backwards compatibility
  - add `selectedLocalLLMSelection`
  - decode old settings as `.ollama`
  - encode new settings with runtime metadata
- Update `AppSettingsCodableTests`.

Tests:

- `LocalLLMRuntimeTests`
  - runtime enum Codable
  - unknown runtime safe fallback
  - empty fresh install has no selected llama.cpp model
  - old `selectedLocalLLMModelName` migrates to `.ollama`
- Existing `AppSettingsCodableTests` still pass.

Acceptance criteria:

- No UI behavior change.
- Existing Ollama path still reads the old selection.
- `./test.sh` passes.

Code-review gate:

- Review persistence compatibility.
- Review that no old user setting is dropped.
- Fix all findings before Sprint 2.

### Sprint 2: Ollama Adapter Behind Shared Model Types

Goal: move Ollama behind runtime-neutral local LLM concepts while preserving behavior.

Tasks:

- Create `OllamaLocalLLMAdapter`.
- Map `OllamaService.InstalledModel` to `LocalLLMInstalledModel`.
- Map `OllamaModelCatalog.Model` to `LocalLLMModelCatalogEntry`.
- Keep `OllamaService` unchanged except for small helper additions if needed.
- Update `LocalModelManager` internals toward runtime-neutral state.
- Keep UI copy mostly unchanged for now.
- Ensure `hasAnyRewriteEngine` still works.

Tests:

- Adapter mapping tests.
- Existing `OllamaModelManagementTests`.
- Existing `LocalModelStateTests`.
- New tests proving Ollama normalization still handles bare name vs `:latest`.

Acceptance criteria:

- Ollama install/start/pull/delete remains unchanged.
- Current local model UI remains functionally identical.
- No llama.cpp behavior exposed yet.

Code-review gate:

- Review no behavior regression.
- Review naming clarity: no new misleading "installed" state.
- Fix findings before Sprint 3.

### Sprint 3: llama.cpp Runtime Process Spike

Goal: prove the app can manage a `llama-server` process safely.

Tasks:

- Add `LlamaCppRuntimeService`.
- Support developer-configured external binary path first:
  - environment variable in tests
  - optional app setting later
- Define server config:
  - binary URL
  - model URL
  - host `127.0.0.1`
  - dynamic port
  - context size
  - alias
  - session API key
- Add `LlamaCppRuntimeState`.
- Implement argument builder.
- Implement start/stop lifecycle.
- Implement `/health` polling.
- Treat `503` as loading, not failure.
- Terminate child process on stop/app quit.
- Log stdout/stderr via `os.Logger`.

Security requirements:

- Never bind to `0.0.0.0`.
- Always use `127.0.0.1`.
- Always use a random per-session API key when supported.
- No CORS or web UI exposure.

Tests:

- `LlamaCppRuntimeTests`
  - command args contain host, port, model, alias, context
  - no `0.0.0.0`
  - missing binary produces actionable error
  - missing model produces actionable error
  - stop is idempotent
  - health `503` maps to loading
  - health `200` maps to ready
  - timeout maps to failed

Acceptance criteria:

- Runtime service is testable without a real model.
- Optional integration test can start a real server if env vars are set.
- App behavior remains unchanged unless hidden/dev runtime is selected.

Code-review gate:

- Review process lifecycle.
- Review local network security.
- Review crash and cleanup behavior.
- Fix findings before Sprint 4.

### Sprint 4: llama.cpp Server Client And Rewrite Provider

Goal: send real rewrite requests through a ready llama.cpp local server.

Tasks:

- Add `LlamaCppServerClient`.
- Add `LlamaCppRewriteProvider`.
- Use `/v1/chat/completions` first.
- Reuse the provider request shape from `OllamaRewriteProvider` where practical.
- Decode OpenAI-compatible responses.
- Map server errors:
  - missing model
  - loading
  - timeout
  - malformed response
  - empty response
  - connection refused
- Ensure no fallback model is silently used.
- Add runtime-specific model ID to `RewriteOutcome`.

Tests:

- `LlamaCppServerClientTests`
  - request JSON shape
  - response decoding
  - OAI-style errors
  - llama.cpp-style errors
  - 503 loading handling
- `LlamaCppRewriteProviderTests`
  - no model selected
  - server unavailable
  - valid response
  - empty response
  - used/requested model IDs equal
- `ArchiveReuseTests`
  - local runtime errors still surface cleanly.

Acceptance criteria:

- Hidden/dev llama.cpp provider can rewrite text against a running `llama-server`.
- OpenAI and Ollama providers still work.
- Provider layer remains transport-only; prompt logic stays in `LLMService`.

Code-review gate:

- Review API contract and version-churn assumptions.
- Review no accidental cloud/network calls.
- Fix findings before Sprint 5.

### Sprint 5: GGUF Model Store, Catalog, And Download

Goal: let rede manage llama.cpp GGUF models without Ollama.

Tasks:

- Add `AppSupportPaths.llamaCppModelsDirectoryURL`.
- Add `LlamaCppModelStore`.
  - installed scan
  - metadata scan
  - partial file exclusion
  - delete
  - disk size
- Add `LlamaCppModelCatalog`.
  - small curated initial model set
  - GGUF only
  - HTTPS URL
  - SHA-256
  - display name
  - quantization
  - approximate size
  - license summary
  - min/recommended RAM
- Add `LlamaCppDownloadService`.
  - download to `.partial`
  - progress
  - checksum
  - atomic move
  - cancel
  - cleanup
- Defer Range resume unless the implementation is simple and well-tested.

Recommended initial catalog policy:

- Start with 1.5B-4B instruct GGUF models.
- Prefer permissive licenses.
- Do not bundle models in the app.
- Show license/source before download.

Tests:

- `LlamaCppModelManagementTests`
  - unique IDs
  - valid HTTPS URLs
  - `.gguf` filenames only
  - size > 0
  - checksum present
  - license present
  - partial files not installed
  - paths remain inside model root
- `LlamaCppDownloadServiceTests`
  - successful download
  - checksum failure
  - cancel
  - HTTP errors
  - progress clamp
  - atomic final install

Acceptance criteria:

- llama.cpp model can be installed without Ollama.
- Corrupt/partial downloads never appear as usable.
- Delete cannot escape the model directory.

Code-review gate:

- Review license metadata.
- Review checksum strategy.
- Review path traversal protections.
- Fix findings before Sprint 6.

### Sprint 6: Runtime-Neutral Local Model UI

Goal: present local LLMs as a rede feature, not an Ollama feature.

Tasks:

- Update `LocalLLMModelPicker`.
- Update `LocalModelsView`.
- Update `LocalModelRowView`.
- Update `ModelsSettingsView`.
- Update onboarding `ModelsStepView`.
- Update `ModeCardView` local copy.
- Add runtime filter/toggle:
  - rede lokal (llama.cpp)
  - Ollama fallback
- Show runtime-specific actions:
  - llama.cpp: download model, start local runtime, loading, ready
  - Ollama: install/start Ollama, pull tag
- Update `DESIGN.md` if new UI state patterns are introduced.

UI truth rules:

- Never show "ready" unless disk state and runtime state are true.
- Never show "installed" for `.partial`.
- Never imply Ollama is required when llama.cpp is selected.
- Never imply network use for rewrite.
- Downloads must be explicit user actions.

Tests:

- View-model or pure state tests where possible.
- Existing model state tests.
- Onboarding view model tests for new copy/state.

Acceptance criteria:

- Fresh user can choose local rewrite without seeing Ollama as a prerequisite.
- Existing Ollama user can still use installed Ollama models.
- Secure local mode copy remains truthful.

Code-review gate:

- Review UX for false readiness.
- Review German copy for clarity.
- Review `DESIGN.md` consistency.
- Fix findings before Sprint 7.

### Sprint 7: Packaging And Helper Bundling

Goal: ship `llama-server` inside rede builds.

Tasks:

- Pin exact llama.cpp ref.
- Add script:
  - fetch/build helper
  - cache build
  - verify checksum
  - output architecture info
- Extend `build.sh`:
  - `--with-llamacpp`
  - `--skip-llamacpp`
  - `LLAMACPP_REF`
  - helper architecture verification
- Decide helper location:
  - preferred: Apple-conformant nested code location
  - avoid `Resources`
- Sign helper before app.
- Avoid using `codesign --deep` for signing.
- Verify app and helper.
- Document universal vs arch-specific strategy.

Architecture strategy:

- Try universal helper first.
- If universal llama.cpp is unstable, ship two signed helpers:
  - `llama-server-arm64`
  - `llama-server-x86_64`
- Runtime selects current architecture.

Tests / commands:

```bash
./test.sh
./build.sh --release --with-llamacpp
test -x rede.app/Contents/MacOS/llama-server
codesign --verify --deep --strict --verbose=2 rede.app
codesign --verify --strict --verbose=2 rede.app/Contents/MacOS/llama-server
lipo -archs rede.app/Contents/MacOS/rede
lipo -archs rede.app/Contents/MacOS/llama-server
```

Acceptance criteria:

- Release app includes helper.
- Helper starts from inside the app bundle.
- Codesign verification passes.
- App still builds without helper for fast dev if `--skip-llamacpp` is used.

Code-review gate:

- Review signing order.
- Review helper location.
- Review build reproducibility.
- Fix findings before Sprint 8.

### Sprint 8: End-To-End Integration And QA Harness

Goal: prove the full local rewrite stack works without Ollama.

Tasks:

- Add optional `LlamaCppIntegrationTests`.
- Use env vars:
  - `REDE_LLAMA_SERVER`
  - `REDE_TEST_GGUF`
- Skip integration tests if env vars absent.
- Add manual QA checklist.
- Add runtime self-test:
  - start server
  - health ready
  - short deterministic rewrite
  - latency measurement
  - memory warning if slow/heavy
- Add crash recovery test/manual scenario.
- Add cancel during generation scenario.
- Add app quit during model load scenario.

Manual QA matrix:

- Clean Mac, no Ollama.
- Mac with Ollama installed but stopped.
- Mac with Ollama running.
- Apple Silicon 8 GB.
- Apple Silicon 16 GB+.
- Intel Mac if supported.
- Offline with installed GGUF.
- Offline during first download.
- Low disk before download.
- Low disk during download.
- Damaged GGUF.
- App restart after model install.
- Archive rerun with llama.cpp runtime.
- Secure local mode with llama.cpp runtime.

Acceptance criteria:

- llama.cpp local rewrite works without Ollama.
- Ollama fallback still works.
- OpenAI still works.
- Secure local mode remains truthful and functional.
- No orphaned helper process after quit.

Code-review gate:

- Run `$code-review` against the entire diff.
- Findings must be fixed or explicitly documented as accepted with rationale.
- Re-run tests after fixes.

### Sprint 9: Hardening And Future-Proofing

Goal: stabilize for long-term maintenance.

Tasks:

- Add llama.cpp API contract tests.
- Add pinned runtime version metadata.
- Add runtime upgrade checklist.
- Add model catalog update checklist.
- Add telemetry-free local diagnostics:
  - runtime version
  - model id
  - startup latency
  - last error category
- Add documentation:
  - local runtime architecture
  - model storage
  - privacy behavior
  - fallback behavior
  - packaging release checklist
- Add deprecation plan for Ollama-only UI names.

Future-proofing rules:

- No llama.cpp upgrade without reading REST API changelog.
- No catalog model without license and checksum.
- No "ready" state without health check.
- No local server binding beyond `127.0.0.1`.
- No model writes inside the app bundle.
- No direct delete outside model root.

Acceptance criteria:

- Architecture docs are current.
- Runtime version is pinned and visible.
- Tests protect API contract and settings migration.

Final review gate:

- Full code review.
- Full verification.
- Manual QA record attached to PR.

## Review And Fix Loop

Every sprint must follow this loop:

1. Implement sprint scope.
2. Run targeted tests.
3. Run full `./test.sh` unless packaging-only and impossible.
4. Run build check appropriate to sprint:
   - early: `./build.sh --debug`
   - packaging/release: `./build.sh --release --with-llamacpp`
5. Run code review.
6. Convert findings into fix tasks.
7. Fix findings.
8. Re-run impacted tests.
9. Update sprint notes.
10. Only then proceed to next sprint.

No phase is considered done while code-review findings remain unresolved.

## Required Final Test Suite

### Unit Tests

- `LocalLLMRuntimeTests`
- `LlamaCppRuntimeTests`
- `LlamaCppServerClientTests`
- `LlamaCppRewriteProviderTests`
- `LlamaCppModelManagementTests`
- `LlamaCppDownloadServiceTests`
- Existing Ollama tests retained.
- Existing AppSettings migration tests expanded.

### Integration Tests

- Optional real `llama-server` startup.
- Optional real tiny GGUF rewrite.
- Health readiness.
- Process stop cleanup.
- Ollama unavailable but llama.cpp working.

### Packaging Tests

- App and helper codesign verification.
- Helper executable exists.
- Architecture verification.
- Release build verification.
- Notarization script dry run where possible.

### Manual QA

- Clean install.
- Local model first download.
- Rewrite workflow.
- Secure local mode.
- Archive rerun.
- Runtime fallback.
- Offline behavior.
- Low disk.
- Cancellation.
- Crash/restart.
- App quit cleanup.

## Definition Of Done

- llama.cpp can run local rewrite without Ollama installed.
- Ollama fallback still works.
- OpenAI rewrite still works.
- Local Whisper transcription still works.
- UI describes local runtime accurately.
- Model install state is truth-based.
- Server binds only to `127.0.0.1`.
- Helper process is cleaned up on quit.
- GGUF downloads are checksum-validated.
- Partial files never appear installed.
- Full unit test suite passes.
- Release build passes.
- Packaging verification passes.
- Code-review findings are fixed.
- Documentation is updated.

## Execution Order For Subagents

Do not run all implementation agents at once. Use this sequence:

1. Track A and Track B in parallel only if write scopes remain separate.
2. Review and merge abstraction changes.
3. Track C starts after Track A types exist.
4. Track E starts after Track C server client contract exists.
5. Track D can run in parallel with Track C after model type definitions stabilize.
6. Track F starts after Track A/B/D expose stable state.
7. Track G starts after Track C proves runtime start/health.
8. Track H reviews every merged phase and owns final verification.

## Sprint Backlog Summary

### P0

- Runtime-neutral settings and migration.
- Ollama adapter preservation.
- llama.cpp process lifecycle.
- llama.cpp rewrite provider.
- GGUF store/download with checksum.
- Localhost-only security.
- Tests for all above.

### P1

- Runtime-neutral UI.
- Bundled helper build/signing.
- Integration harness.
- Manual QA matrix.

### P2

- Range resume.
- External GGUF import.
- Runtime self-test dashboard.
- MLX evaluation spike.
- Ollama UI demotion to advanced fallback.

## Current Worktree State

- Worktree: `/Users/jasonrinnert/rede-llamacpp`
- Branch: `codex/llamacpp-runtime`
- Existing planning docs:
  - `docs/PLAN-llamacpp-runtime.md`
  - `docs/SPRINT-llamacpp-runtime.md`

## Immediate Next Action

Start Sprint 0 verification and then Sprint 1 implementation with TDD.

Do not begin implementation until this sprint plan is accepted.
