<div align="center">

# ⚡ Blitztext — Local AI Edition

**A native macOS menu-bar app for dictation, transcription and AI rewriting that runs entirely on your Mac.**

Speak into any text field, get clean text back. Rewrite e-mails, prompts and messages with a local LLM — no cloud, no account, no telemetry. Bring your own OpenAI key only if you _want_ the online path.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Universal](https://img.shields.io/badge/Universal-arm64%20%2B%20x86__64-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)
![Local-first](https://img.shields.io/badge/Local--first-no%20telemetry-brightgreen)
![llama.cpp](https://img.shields.io/badge/Local%20AI-llama.cpp-purple)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

</div>

> **Fork status.** This is a heavily extended, local-first edition of the original open-source Blitztext menu-bar app. It started as a simple speech-to-text helper and grew into a full local-AI writing workflow — a bundled **llama.cpp** runtime, a dynamic GGUF model catalog with hardware-aware recommendations, semantic memory and a redesigned interface. No hosted backend, no warranty, no support guarantee. The in-app UI is German by design; the project is documented in English.
>
> The point isn't a one-click finished product. It's a _hackable_, complete example of how a small native macOS app can combine dictation, local models, rewrite modes, memory and context. Clone it, build it, read the code, change it.

---

## ✨ Highlights

- 🎙️ **Dictate anywhere** — global hotkey, live recording pill, instant paste into the focused app.
- 🧠 **Rewrite locally** — turn rough speech into clean e-mails, prompts or messages with an on-device LLM.
- 📦 **Bundled llama.cpp runtime** — no separate install, no `ollama pull`, no Docker. The app ships and manages everything.
- 🗂️ **Dynamic model catalog** — curated GGUF models, a **live Hugging Face feed** that auto-discovers new models (Gemma 4, gpt-oss…), and a field to drop in **any `.gguf` URL** yourself.
- 🎯 **Hardware-aware recommendation** — the app knows your RAM and suggests the best model that fits (e.g. _Qwen3-32B_ on a 48 GB Mac, _Qwen3-1.7B_ on an 8 GB Mac).
- 🔒 **Genuinely private** — in local mode nothing leaves the machine. Online calls go straight to OpenAI with _your_ key, stored only in the Keychain.
- ⌨️ **Per-mode hotkeys**, ✍️ **custom modes**, 🧩 **vocabulary learning**, and opt-in **semantic e-mail memory** — all local.

---

## 📸 Screenshots

|                     Menu bar                      |                        Local models                        |                       Modes                       |
| :-----------------------------------------------: | :--------------------------------------------------------: | :-----------------------------------------------: |
| ![Menu bar popover](docs/screenshots/menubar.png) | ![Local models manager](docs/screenshots/local-models.png) | ![Mode configuration](docs/screenshots/modes.png) |
|       Pick a mode, see its hotkey & backend       |    Install, activate/deactivate & recommend GGUF models    | Tune prompts, tone, memory & enrichment per mode  |

> _Screenshots live in `docs/screenshots/`. Drop in your own captures of the current build to refresh them._

---

## 🧭 What it does

Blitztext lives in the menu bar. Each **mode** is a hotkey that records your voice, transcribes it, and optionally rewrites it — then pastes the result straight into whatever app you're using.

| Mode               | Hotkey idea   | What it does                                                          |
| ------------------ | ------------- | --------------------------------------------------------------------- |
| **Diktat**         | `fn + Shift`  | Pure speech → text. Nothing else.                                     |
| **Textverbessern** | `fn + Ctrl`   | "Speak it written" — clean up rambling dictation into polished prose. |
| **E-Mail**         | custom        | Turn spoken notes into a structured e-mail draft.                     |
| **Prompt**         | `fn + Option` | Convert rough intent into a sharp prompt for other AI tools.          |
| **Social**         | `fn + Cmd`    | Add tasteful emoji / soften the tone.                                 |
| **Dampf ablassen** | custom        | Frustration in → calm, usable message out.                            |

Every mode is **fully configurable** — rename it, rebind its hotkey, pick its backend (online/local), write a custom system prompt, set tone & context, and turn memory/enrichment on or off. Duplicate a mode to keep separate setups for different clients or contexts.

---

## 🧠 Local AI — the core of this fork

Local rewriting runs on a **bundled [llama.cpp](https://github.com/ggml-org/llama.cpp) server** that the app starts as a subprocess on `127.0.0.1`. There is **no Ollama and no external runtime** — Blitztext downloads GGUF model files, verifies them, and runs them itself.

### A model catalog that grows by itself

The **Local Models** window organizes everything in one place — installed models on top (activate / deactivate / delete), with the full catalog tucked behind a collapsible _"Weitere Modelle laden"_ section so the page is never a wall of choices.

That section has **three sources**:

1. **Curated** — a hand-picked, checksum-pinned set that covers every Mac size:
   - **Qwen3** · 1.7B / 4B / 8B / 14B / 32B
   - **Gemma 3** · 4B / 12B / 27B
2. **Live Hugging Face feed** — queries trusted orgs (`ggml-org`) and surfaces their newest GGUFs automatically, so models like **Gemma 4** and **gpt-oss** appear _without an app update_. Junk repos (embedding/vision/test) are filtered out, models too large for your Mac are hidden, and the LFS hash is still verified on download.
3. **Your own URL** — paste a direct link to any `.gguf` file and download it on the spot. Perfect for a niche fine-tune the catalog doesn't know about.

### It recommends the right model for _your_ Mac

Blitztext reads your chip, RAM and free disk and ranks the catalog by quality _within your budget_:

> ✨ **Empfohlen für deinen Mac** — _Qwen3 · 32B · Q4_K_M_ · "Best quality that fits comfortably in your 48 GB of RAM."

Models that wouldn't run are hidden; tight-but-usable ones are shown without being recommended. Big models load fast on subsequent runs — the integrity check happens once at download, not on every cold start.

### Privacy of the local path

- The llama.cpp server binds to `localhost` only, with a per-launch API key.
- Audio is transcribed locally via **WhisperKit / Core ML**; temp audio is deleted after processing.
- Nothing is uploaded, logged or phoned home. Use the app fully offline.

---

## ☁️ Online path (optional)

Prefer the cloud for a specific mode? Set a mode's backend to **Online** and Blitztext uses the **OpenAI API directly** with your own key:

- Transcription via OpenAI Audio Transcriptions (25 MB upload limit, enforced early).
- Rewriting via Chat Completions.
- The key lives **only in the macOS Keychain** — there is no proxy and no telemetry in between.

You can mix and match per mode: dictate locally, rewrite online, or the reverse.

---

## 🧩 Memory, vocabulary & context (all opt-in, all local)

- **Semantic e-mail memory** — an opt-in local vector store embeds your past rewrites (via a local **nomic-embed-text** GGUF on a second llama.cpp server) and retrieves similar earlier drafts as background context. Capped, retention-aware, never uploaded.
- **Vocabulary & term learning** — frequently used names and domain terms are learned and injected into future prompts, with fuzzy correction for tricky words.
- **Context awareness** — modes can optionally include the focused window, your current text selection, and content-type hints in the prompt.
- **Two-variant preview** — a rewrite mode can pause in the floating pill and let you choose which version to insert.

---

## 🔐 Privacy & security

- **Local-first & fail-closed** — local modes never silently fall back to the cloud.
- **No App Sandbox by design**, but a tight entitlement set (audio input + network client only).
- **`URLSessionConfiguration.ephemeral`** for network calls; temp audio deleted after use.
- **Keychain-only** storage for your OpenAI key. **No accounts, no analytics, no hosted backend.**

Read [docs/privacy.md](docs/privacy.md) before using with sensitive content.

### Data flow

```text
Online transcription:  Your Mac → OpenAI Audio Transcriptions API
Online rewriting:      Your Mac → OpenAI Chat Completions API
Local transcription:   Your Mac → WhisperKit / Core ML (on device)
Local rewriting:       Your Mac → bundled llama.cpp server (localhost)
E-mail embeddings:     Your Mac → bundled llama.cpp embedding server (localhost)
Model downloads:       Hugging Face → your Mac (checksum-verified GGUF files)
```

---

## ✅ Requirements

- macOS **14.0+** (Sonoma or newer), Apple Silicon or Intel.
- For **local AI**: a few GB of free disk per model (~1.3 GB for the smallest, ~20 GB for the largest).
- For the **online path**: your own OpenAI API key (e.g. `gpt-4o-mini` / `gpt-4o` for rewriting, `whisper-1` for transcription).
- **Microphone** permission, and **Accessibility** permission for direct paste.

The build pulls one Swift Package automatically: [`argmax-oss-swift`](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) for on-device transcription.

---

## 🛠️ Build & run from source

Requires full **Xcode 16+** and [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `BlitztextMac/project.yml` — edit that, not the `.xcodeproj`.

```bash
git clone https://github.com/aslomon/blitztext-app.git
cd blitztext-app

# 1. Build the bundled llama.cpp helper (universal binary + companion dylibs)
./scripts/build-llamacpp-helper.sh
# → prints the helper path and its SHA256

# 2. Build, install to /Applications and launch — bundling that helper
./build.sh --debug --install --run \
  --llamacpp-helper="<path-from-step-1>" \
  --llamacpp-helper-sha256="<sha-from-step-1>"

# Release build:
./build.sh --release --llamacpp-helper="…" --llamacpp-helper-sha256="…"

# Tests (pinned to arm64):
./test.sh
```

For quick UI iteration without the local runtime, build with `--allow-missing-llamacpp-helper` (local rewrite is then unavailable). The generated `.app` is ad-hoc signed for local development only — a public release would need Developer ID signing + notarization.

On first launch: grant **Microphone** (and **Accessibility** for direct paste), optionally enter your **OpenAI key**, and open **Local Models** to download a GGUF model. For a slower walkthrough see [docs/setup.md](docs/setup.md) and [docs/local-models.md](docs/local-models.md).

### Permissions

- **Microphone** — to record your voice.
- **Accessibility** — to paste the result back into the focused app. Without it, you can still copy results manually.

If auto-paste fails even though transcription works, enable Blitztext under **System Settings → Privacy & Security → Accessibility**, restart it, and remove any stale duplicate entries. Full Disk Access is _not_ required.

---

## 🏗️ Architecture (in one breath)

Layered **App → Features → Services**, native Swift + SwiftUI + AppKit:

```text
BlitztextMac/
  App/        Lifecycle, paste handling, menu-bar/pill/onboarding/local-models windows, AppState
  Features/   Workflows, menu-bar UI, onboarding, settings, local-model UI
  Services/   Recording, transcription (WhisperKit + OpenAI), the llama.cpp runtime/catalog/
              download/embedding stack, hotkeys, storage, memory, context capture
  Tests/      XCTest suite for pure logic, Codable migrations, prompts and decisions
build.sh      Local build + signing; scripts/build-llamacpp-helper.sh builds the runtime
docs/         Setup, privacy, local models, roadmap and planning notes
```

Installed models are **self-describing via on-disk manifests**, so curated, Hugging-Face-fetched and custom-URL models all download, list and run through the same path.

---

## 🔀 How this differs from the original

The upstream project is a lightweight speech-to-text helper. This fork adds, among other things:

- A **bundled llama.cpp runtime** that replaces the earlier Ollama dependency entirely.
- A **dynamic, self-expanding model catalog** + hardware-aware recommendations + custom-URL models.
- **Semantic e-mail memory** with local embeddings, vocabulary learning and context-aware prompting.
- A **redesigned interface**, a live dictation pill, configurable modes, rebindable hotkeys, two-variant previews, onboarding, code signing and a real test suite.

---

## 🤝 Contributing & support

Contributions are welcome — especially anything that makes the project easier to build, understand or fork. Please read [CONTRIBUTING.md](CONTRIBUTING.md). There's no formal support promise; see [SUPPORT.md](SUPPORT.md) for how to ask for help without sharing secrets, and [ROADMAP.md](ROADMAP.md) for direction.

---

## 📄 License

Code is released under the **MIT License** — see [LICENSE](LICENSE). Project names, logos and app icons are not automatically granted as trademarks; see [TRADEMARKS.md](TRADEMARKS.md).

Local models are downloaded from **Hugging Face** (`ggml-org` and others) under their respective licenses (Apache-2.0, Gemma Terms, etc.). The bundled runtime is **llama.cpp** by ggml-org. Based on the original open-source **Blitztext** by [cmagnussen](https://github.com/cmagnussen/blitztext-app).

## Legal / Impressum & Datenschutz

This is an experimental, non-commercial open-source project, provided as-is under the MIT License without warranty or support. Nothing is sold here and no installation or operation is performed on your behalf.

The companion website (blitztext.de) is operated by Blackboat Internet GmbH:

- Impressum: https://www.blackboat.com/impressum
- Datenschutz / Privacy: https://www.blackboat.com/datenschutz

<div align="center">

**Made for people who'd rather talk than type — and keep their words on their own machine.**

</div>
