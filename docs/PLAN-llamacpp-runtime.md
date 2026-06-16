# Implementation Plan: Embedded llama.cpp Runtime

## Requirements Restatement

- rede should eventually run local rewrite LLMs without requiring users to install Ollama.
- The preferred embedded path should use llama.cpp, specifically a bundled `llama-server` helper process for the first production-ready implementation.
- Ollama should not be removed in a single step. It should remain available as a fallback/legacy runtime while llama.cpp is introduced.
- The existing rewrite prompt logic must stay provider-agnostic. `RewriteProvider` should remain the boundary for OpenAI, Ollama, and llama.cpp.
- The local model UI should become runtime-neutral: users choose "local language model", not an Ollama-only concept.
- Model downloads must be user-friendly, resumable where possible, checksum-aware, and stored under rede application support.
- All changes should be built in this worktree on branch `codex/llamacpp-runtime`, then reviewed before merging to `main`.

## Decision

Use **bundled `llama-server` as a helper process** for the first llama.cpp implementation.

Do not start with in-process Swift/C++ bindings or a static llama.cpp library. The helper-process approach keeps rede's Swift app simple, preserves the existing HTTP provider pattern, avoids C++ ABI and lifecycle issues, and lets us replace or pin the llama.cpp binary independently.

Official basis:

- llama.cpp describes itself as C/C++ local LLM inference with Apple Silicon optimized through ARM NEON, Accelerate, and Metal.
- llama.cpp quick start supports `llama-server` as an OpenAI-compatible API server.
- llama.cpp has official API churn notes for `llama-server`, so the runtime version must be pinned.
- MLX remains a later Apple-Silicon-only optimization path, not the broad first implementation.

## Target Architecture

### Provider Layer

- Keep `RewriteProvider` unchanged for rewrite workflows.
- Add `LlamaCppRewriteProvider` that calls a locally managed `llama-server` OpenAI-compatible endpoint.
- Keep `OllamaRewriteProvider` during migration.
- `AppState.rewriteProvider(for:)` should select the configured local runtime.

### Runtime Layer

Introduce runtime-neutral local LLM types:

- `LocalLLMRuntimeKind`
  - `.llamaCpp`
  - `.ollama`
- `LocalLLMSelection`
  - runtime kind
  - model id
  - display name
  - model file path or runtime tag
- `LocalLLMInstalledModel`
  - id
  - display name
  - runtime
  - size bytes
  - metadata
- `LocalLLMModelCatalogEntry`
  - id
  - runtime
  - display name
  - download URL or runtime tag
  - expected size
  - checksum
  - quantization
  - license metadata
  - hardware recommendation metadata

### llama.cpp Services

- `LlamaCppRuntimeService`
  - finds bundled `llama-server`
  - chooses local port
  - starts/stops `Process`
  - waits for `/health`
  - restarts after crash when appropriate
  - exposes base URL to `LlamaCppRewriteProvider`
- `LlamaCppModelStore`
  - stores GGUF files under `Application Support/rede/models/llamacpp`
  - detects complete vs partial downloads
  - removes models
  - reports disk usage
- `LlamaCppDownloadService`
  - downloads GGUF files
  - writes to `.partial`
  - validates checksum
  - moves atomically to final file
  - reports progress
- `LlamaCppModelCatalog`
  - curated GGUF entries for rede rewrite use cases
  - starts small: 1.5B-4B instruct models
  - includes RAM/disk guidance
- `LlamaCppServerClient`
  - checks `/health`
  - optionally checks `/v1/models`
  - sends `/v1/chat/completions`
  - decodes OpenAI-compatible responses

### Existing Ollama Adapter

Wrap the current Ollama services behind the same runtime-neutral concepts:

- `OllamaService` remains for `/api/tags`, `/api/pull`, `/api/delete`.
- `OllamaInstallerService` remains as fallback setup path.
- `OllamaModelCatalog` can stay initially, then be converted to `LocalLLMModelCatalogEntry`.

## Implementation Phases

### Phase 1: Runtime-Neutral Model Types

- Add `LocalLLMRuntime.swift` with the shared local runtime enums and structs.
- Add unit tests for Codable compatibility and migration defaults.
- Add `LocalLLMSelection` to `AppSettings` while preserving `selectedLocalLLMModelName` for migration.
- Keep existing behavior unchanged: default local runtime remains Ollama until llama.cpp is ready.

Acceptance criteria:

- Existing Ollama tests still pass.
- Existing app settings decode old settings without data loss.
- No UI behavior changes yet.

### Phase 2: Ollama Adapter Behind Shared Types

- Introduce an adapter layer that maps current Ollama installed models and catalog entries to runtime-neutral local LLM models.
- Update `LocalModelManager` internally toward `LocalLLMManager` semantics without renaming all UI files yet.
- Keep Ollama UI copy mostly unchanged in this phase.
- Add tests for installed model normalization through the adapter.

Acceptance criteria:

- Ollama installation and model pull still work.
- Current local model picker still shows installed Ollama models.
- Tests pass before adding llama.cpp.

### Phase 3: llama.cpp Runtime Process Spike

- Add `LlamaCppRuntimeService`.
- Support a developer-provided `llama-server` binary path first.
- Add process lifecycle:
  - start with `--host 127.0.0.1`
  - dynamic port
  - model path
  - context size
  - model alias
  - stop on app quit
- Add `/health` polling with clear loading, ready, and failed states.
- Add tests for command argument construction and port selection without launching a real server.

Acceptance criteria:

- Unit tests cover process config.
- App can detect "llama.cpp runtime unavailable" cleanly.
- No production bundle dependency yet.

### Phase 4: `LlamaCppRewriteProvider`

- Add provider that talks to `llama-server` via `/v1/chat/completions`.
- Reuse the same request/response shape as `OllamaRewriteProvider` where possible.
- Add explicit error mapping:
  - server unavailable
  - model missing
  - generation timeout
  - empty response
  - malformed response
- Add tests with mocked HTTP responses.

Acceptance criteria:

- A local rewrite can use llama.cpp when a server is ready.
- Errors surface as `LLMError.localModelUnavailable` or `LLMError.networkError` with actionable copy.
- No OpenAI or Ollama logic regresses.

### Phase 5: GGUF Model Store And Catalog

- Add `LlamaCppModelCatalog` with a small curated set of GGUF models.
- Add `LlamaCppModelStore` for installed model discovery.
- Add model metadata:
  - display name
  - Hugging Face repo/file
  - direct download URL
  - approximate download size
  - expected SHA-256
  - quantization
  - license summary
  - recommended RAM tier
- Add tests for catalog integrity and store path handling.

Acceptance criteria:

- The app can list llama.cpp catalog entries without contacting a server.
- Installed GGUF files are detected reliably.
- Partial files do not count as installed.

### Phase 6: Download Manager For GGUF Models

- Add `LlamaCppDownloadService`.
- Download to a partial path first.
- Validate checksum before install.
- Move atomically to the final model path.
- Support cancel and cleanup.
- Decide whether HTTP range resume is worth implementing in the first pass.

Acceptance criteria:

- Downloads are progress-aware.
- Interrupted downloads never appear as installed.
- Checksum failures are visible and recoverable.

### Phase 7: Local Model UI Runtime Selection

- Rename user-facing language from Ollama-only to local runtime-neutral copy:
  - "Lokales Sprachmodell"
  - "Runtime: rede lokal (llama.cpp)"
  - "Fallback: Ollama"
- Keep advanced/developer access to Ollama.
- Update `LocalModelsView`, `LocalModelRowView`, `LocalLLMModelPicker`, `ModelsSettingsView`, and onboarding copy.
- Add runtime status banners:
  - llama.cpp helper missing
  - model missing
  - server starting/loading model
  - ready
  - fallback to Ollama available

Acceptance criteria:

- User can choose llama.cpp model first.
- User can still use Ollama if desired.
- UI remains consistent with `DESIGN.md`.

### Phase 8: Bundle `llama-server`

- Pin a llama.cpp release/build id.
- Add a repeatable script to fetch/build `llama-server`.
- Add checksums for the helper binary.
- Copy helper into `rede.app/Contents/MacOS/llama-server`.
- Update signing script so the helper is signed with the app.
- Verify universal target strategy:
  - preferred: universal helper if available/buildable
  - fallback: architecture-specific helper selected at build/package time

Acceptance criteria:

- Release app contains the helper.
- `codesign --verify` succeeds.
- Existing `./build.sh --release` still produces a working app.

### Phase 9: End-To-End Verification

- Add integration test mode that can run with a tiny GGUF test model when present.
- Manual QA matrix:
  - clean Mac with no Ollama
  - Mac with Ollama installed but not running
  - Apple Silicon 8 GB
  - Apple Silicon 16 GB+
  - Intel Mac if available
- Measure:
  - cold startup
  - warm rewrite latency
  - memory usage
  - timeout behavior
  - crash recovery

Acceptance criteria:

- llama.cpp local rewrite works without Ollama.
- Ollama fallback still works.
- OpenAI workflow still works.
- Existing tests and release build pass.

## Dependencies

- Pinned llama.cpp release/build.
- Bundled `llama-server` binary or reproducible local build script.
- Curated GGUF models with clear licenses and checksums.
- Existing `RewriteProvider`, `LLMService`, `AppState`, `LocalModelManager`, and settings UI.
- macOS `Process` lifecycle handling.
- Code signing and release packaging updates.

## Risks

- HIGH: `llama-server` API changes. Mitigation: pin exact version and add response contract tests.
- HIGH: model licensing and redistribution constraints. Mitigation: download models explicitly with license metadata; do not bundle models initially.
- HIGH: helper packaging/signing breaks release builds. Mitigation: add packaging phase late, after runtime spike works with external binary.
- MEDIUM: memory estimates are wrong for GGUF + KV cache. Mitigation: conservative RAM tiers and runtime self-test.
- MEDIUM: local port conflicts. Mitigation: dynamic port and localhost-only binding.
- MEDIUM: startup latency feels broken. Mitigation: visible "model loading" state and prewarm after selection.
- MEDIUM: cancellation leaves helper in bad state. Mitigation: cancel request first; restart helper if needed.
- LOW: keeping Ollama fallback creates extra UI complexity. Mitigation: hide under advanced fallback once llama.cpp is stable.

## Subagent / Parallel Work Plan

- Agent A: Runtime abstraction and AppSettings migration.
- Agent B: llama.cpp runtime process service and server client.
- Agent C: GGUF catalog, model store, and download/checksum service.
- Agent D: UI copy and local model management view updates.
- Agent E: packaging/signing/build script changes.
- Agent F: tests, integration harness, and manual QA checklist.

Do not run all agents immediately against the same files. Split ownership by file set to avoid merge conflicts.

## Initial File Ownership Proposal

- Runtime abstraction:
  - `RedeMac/Services/LocalLLMRuntime.swift`
  - `RedeMac/Features/Workflows/WorkflowProtocol.swift`
  - `RedeMac/Tests/AppSettingsCodableTests.swift`
- llama.cpp runtime:
  - `RedeMac/Services/LlamaCppRuntimeService.swift`
  - `RedeMac/Services/LlamaCppServerClient.swift`
  - `RedeMac/Tests/LlamaCppRuntimeTests.swift`
- Model store/catalog/download:
  - `RedeMac/Services/LlamaCppModelCatalog.swift`
  - `RedeMac/Services/LlamaCppModelStore.swift`
  - `RedeMac/Services/LlamaCppDownloadService.swift`
  - `RedeMac/Tests/LlamaCppModelManagementTests.swift`
- Provider:
  - `RedeMac/Services/Providers/RewriteProvider.swift`
  - `RedeMac/App/AppState.swift`
- UI:
  - `RedeMac/Features/Settings/LocalModelsView.swift`
  - `RedeMac/Features/Settings/LocalModelRowView.swift`
  - `RedeMac/Features/Settings/LocalLLMModelPicker.swift`
  - `RedeMac/Features/Settings/ModelsSettingsView.swift`
  - `RedeMac/Features/Onboarding/Steps/ModelsStepView.swift`
- Packaging:
  - `build.sh`
  - `RedeMac/project.yml`
  - `scripts/`

## Estimated Complexity

HIGH.

This is a multi-phase runtime migration with packaging, UI, model-download, and process-lifecycle work. The safest path is to merge it in small PRs:

1. Runtime-neutral abstraction with Ollama still working.
2. llama.cpp external-binary spike.
3. llama.cpp provider and model store.
4. UI runtime selection.
5. bundled helper packaging.

## Immediate Next Step After Approval

Start Phase 1 in this worktree with TDD:

1. Add tests for `LocalLLMRuntimeKind` and `LocalLLMSelection` decoding old settings.
2. Add runtime-neutral structs.
3. Wire them into `AppSettings` without changing current behavior.
4. Run `./test.sh`.

**WAITING FOR CONFIRMATION**: Proceed with Phase 1 implementation in this worktree?
