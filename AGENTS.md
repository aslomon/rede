# Repository Guidelines

> See also: [`agent.md`](agent.md), [`DESIGN.md`](DESIGN.md), and [`CLAUDE.md`](CLAUDE.md) for deeper project guidance.

## Project Structure & Module Organization

This repository contains `rede`, a native macOS menu bar app. Main source code lives in `RedeMac/`:

- `App/`: app entry point, window/controllers, shared app state.
- `Features/`: SwiftUI feature areas such as onboarding, settings, menu bar, workflows, and shared UI.
- `Services/`: transcription, rewrite, memory, model, permissions, updates, and local runtime services.
- `Views/`: reusable visual views outside a specific feature.
- `Resources/`: entitlements, `Info.plist`, assets, icons, and app resources.
- `Tests/`: XCTest unit tests named `FeatureOrServiceTests.swift`.

Project generation is driven by `RedeMac/project.yml`. Generated `.xcodeproj` and `.derivedData-*` directories are build artifacts.

## Build, Test, and Development Commands

- `./build.sh --debug`: generate the Xcode project and build Debug.
- `./build.sh --release`: build universal Release.
- `./build.sh --debug --run`: build and launch locally.
- `./test.sh`: run XCTest unit tests on macOS arm64.
- `scripts/create-dev-cert.sh`: create the local signing identity for stable Accessibility permissions.
- `scripts/build-llamacpp-helper.sh`: build the bundled llama.cpp helper.

Requires Xcode 16+, Command Line Tools, and XcodeGen.

## Coding Style & Naming Conventions

Use Swift 5.10 and existing SwiftUI/AppKit patterns. Prefer small, testable types; keep pure logic in services or view models, not SwiftUI views. Name files after their primary type, for example `LlamaCppRuntimeService.swift`. Use descriptive `test...` names.

For UI work, read `DESIGN.md` first and follow its visual system.

## Testing Guidelines

Add or update XCTest coverage for behavior changes, especially parsing, persistence, privacy boundaries, local models, and formatting helpers. Place tests in `RedeMac/Tests` and import with `@testable import rede`. Run `./test.sh`; run `./build.sh --debug` when touching app wiring, resources, signing, or project configuration.

## Commit & Pull Request Guidelines

Commit messages use short imperative summaries, for example `Fix popover arrow background mismatch on macOS 26`. Keep commits focused and avoid unrelated cleanup.

Pull requests should include what changed, why, how it was tested, and whether AI-assisted coding tools were used. Link issues when relevant. Include screenshots for UI changes. Call out privacy, security, data-flow, signing, or update-mechanism changes.

## Security & Configuration Tips

Never commit API keys, tokens, private recordings, transcripts, downloaded model files, or signing material. Keep remote-service additions intentional and documented. CI runs a secret hygiene scan; update `.github/secret-scan-patterns.txt` when new sensitive token formats matter.
