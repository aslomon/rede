<div align="center">

# 💬 rede

### Sprich. Es wird Text. Auf deinem Mac, für deinen Mac.

**A native macOS menu-bar app that turns your voice into finished text — a clean e-mail, a sharp AI prompt, a social post — using a local LLM that runs entirely on your machine.**

No account. No cloud requirement. No telemetry. Bring your own OpenAI key only if you _want_ the online path.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Universal](https://img.shields.io/badge/Universal-arm64%20%2B%20x86__64-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)
![Local-first](https://img.shields.io/badge/Local--first-no%20telemetry-brightgreen)
![llama.cpp](https://img.shields.io/badge/Local%20AI-llama.cpp-purple)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

**[↓ Download](https://github.com/aslomon/rede/releases/latest)** · **[🌐 Website](https://aslomon.github.io/rede/)** · **[📸 Screenshots](#-screenshots)** · **[🛠️ Build from source](#️-build--run-from-source)**

</div>

> 🇩🇪 The app UI is **German** (informal, by design). Code, docs and this README are English.

---

## Why rede is not "just another dictation app"

Most Mac dictation tools stop at speech-to-text. rede starts there and keeps going: it **transcribes**,
then **rewrites** what you said into the thing you actually need — and it does the AI part **locally**,
on a model it downloads and runs itself. It **learns your words**, **remembers how you write**, and
**recommends the right model for your exact Mac**. It's free, open source (MIT), and German-first.

The honest one-liner: **a local-AI writing workflow that happens to start with your voice.**

---

## 🔥 What makes it special

### 🧠 A bundled local-AI runtime — zero setup

Local rewriting runs on a **bundled [llama.cpp](https://github.com/ggml-org/llama.cpp) server** the app
starts on `127.0.0.1`. **No Ollama, no Docker, no `pip install`, no separate runtime.** rede downloads
GGUF model files, checksum-verifies them, and runs them itself — and so does transcription
(**WhisperKit / Core ML**, on device). In local mode, **nothing leaves your Mac.**

### 🗂️ A model catalog that grows by itself — and picks the right model _for your Mac_

This is the part nobody else does:

- **Curated, checksum-pinned models** covering every Mac size (Qwen3 1.7B→32B, Gemma 3 4B→27B).
- **A live Hugging Face feed** that auto-discovers brand-new GGUFs from trusted orgs — models like
  Gemma 4 or gpt-oss show up **without an app update**. Junk repos are filtered, oversized models
  hidden, LFS hashes verified on download.
- **Any `.gguf` URL** — paste a link to a niche fine-tune and run it on the spot.
- **Hardware-aware recommendation** — rede reads your chip, RAM and free disk and tells you the best
  model that _fits comfortably_: _Qwen3-32B_ on a 48 GB Mac, _Qwen3-1.7B_ on an 8 GB Mac. Models that
  won't run are hidden; tight-but-usable ones are shown but not pushed.

### 🧩 Memory that actually learns from you (all local, all opt-in)

- **Semantic e-mail memory** — opt in, and the more you dictate, the better it gets. A **local vector
  store** (a `nomic-embed-text` GGUF on a second llama.cpp server) embeds your finished drafts so rede
  can recall **how you phrased similar cases before** and feed that back as quiet background context.
  Capped, retention-aware, never uploaded.
- **Vocabulary & term learning** — your names, jargon and domain terms are learned and injected into
  future prompts, with **fuzzy correction** for words Whisper mangles.
- **Correction learning** — rede mines the edits you make to its output and gets better at _your_ style
  over time.

### 🎯 Five purpose-built modes — speech in, the _finished thing_ out

Not five settings — five different finished artifacts. Each is a hotkey; each is fully configurable.

### ✍️ The thoughtful details

- **Two-variant preview** — turn it on per mode and a rewrite pauses with **two versions** in the
  floating pill; pick the one you like.
- **Context awareness** — modes can optionally read the focused field, your text selection and
  content-type hints to ground the rewrite.
- **Improve-your-prompt** — every mode's system prompt is yours to edit, with a one-click
  "verbessern" that sharpens it using the same local/online engine.
- **It just pastes** — the result lands in the field you're already in, with a copy-only fallback if
  paste is blocked. Opt-in everything; calm defaults.

---

## 🎛️ The five modes

| Mode             | Default hotkey      | Speech in → finished thing out                                                              |
| ---------------- | ------------------- | ------------------------------------------------------------------------------------------- |
| **Diktat**       | `fn + Shift`        | Pure speech → clean text via OpenAI. Nothing else.                                          |
| **Diktat lokal** | `fn + Shift + Ctrl` | Speech → text fully on-device with Whisper. No audio leaves your Mac.                       |
| **E-Mail**       | `fn + Ctrl`         | Rough spoken notes → a structured, ready-to-send e-mail (reads Sie/Du, uses field context). |
| **Prompt**       | `fn + Option`       | A dictated task → a precise prompt for AI coding agents like Claude Code or Codex.          |
| **Social**       | `fn + Cmd`          | Spoken text → a social post with tasteful emoji (density adjustable).                       |

Rename any mode, rebind its hotkey, switch its backend (online/local), rewrite its system prompt, set
tone & context, toggle memory/enrichment — or duplicate it for a different client or context.

---

## 📸 Screenshots

|                     Menu bar                      |                        Local models                        |                       Modes                       |
| :-----------------------------------------------: | :--------------------------------------------------------: | :-----------------------------------------------: |
| ![Menu bar popover](docs/screenshots/menubar.png) | ![Local models manager](docs/screenshots/local-models.png) | ![Mode configuration](docs/screenshots/modes.png) |
|       Pick a mode, see its hotkey & backend       |   Install, activate & recommend GGUF models for your Mac   |  Tune prompt, tone, memory & enrichment per mode  |

---

## 🔐 Privacy — by proof, not by promise

You don't have to trust a marketing claim; **the code is open, read it.**

- **Local-first & fail-closed** — local modes never silently fall back to the cloud.
- **No App Sandbox by design**, but a tight entitlement set (audio input + network client only).
- **`URLSessionConfiguration.ephemeral`** for network calls; temp audio deleted after use.
- **Keychain-only** storage for your OpenAI key. **No accounts, no analytics, no hosted backend.**

```text
Online transcription:  Your Mac → OpenAI Audio Transcriptions API
Online rewriting:      Your Mac → OpenAI Chat Completions API
Local transcription:   Your Mac → WhisperKit / Core ML (on device)
Local rewriting:       Your Mac → bundled llama.cpp server (localhost)
E-mail embeddings:     Your Mac → bundled llama.cpp embedding server (localhost)
Model downloads:       Hugging Face → your Mac (checksum-verified GGUF files)
```

The online path (optional) goes **straight to OpenAI with your own key** — no proxy, no telemetry in
between. Mix per mode: dictate locally, rewrite online, or the reverse. Read
[docs/privacy.md](docs/privacy.md) before using with sensitive content.

---

## 🔄 Updates

A daily (and on-demand) check against the release feed, powered by [Sparkle](https://sparkle-project.org):
one HTTPS request for the appcast carrying only the app version — no profile, no identifiers, and an off
switch. Update archives are **EdDSA-signed** and verified before extraction.

---

## ✅ Requirements

- macOS **14.0+** (Sonoma or newer), Apple Silicon or Intel.
- For **local AI**: a few GB of free disk per model (~1.3 GB smallest, ~20 GB largest).
- For the **online path**: your own OpenAI API key.
- **Microphone** permission, and **Accessibility** permission for direct paste.

The build pulls one Swift Package automatically: [`argmax-oss-swift`](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit).

---

## 🛠️ Build & run from source

Requires full **Xcode 16+** and [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The Xcode project is generated from `BlitztextMac/project.yml` — edit that, not the `.xcodeproj`.

```bash
git clone https://github.com/aslomon/rede.git
cd rede

# 1. Build the bundled llama.cpp helper (universal binary + companion dylibs)
./scripts/build-llamacpp-helper.sh        # → prints the helper path and its SHA256

# 2. Build, install to /Applications and launch — bundling that helper
./build.sh --debug --install --run \
  --llamacpp-helper="<path-from-step-1>" \
  --llamacpp-helper-sha256="<sha-from-step-1>"

./build.sh --release --llamacpp-helper="…" --llamacpp-helper-sha256="…"   # release build
./test.sh                                                                  # tests (arm64)
```

For quick UI iteration without the runtime, add `--allow-missing-llamacpp-helper` (local rewrite is then
unavailable). The dev `.app` is ad-hoc signed; a public release needs Developer ID signing + notarization.
On first launch, the onboarding wizard walks you through permissions, processing path, models and a safe
test dictation. Slower walkthrough: [docs/setup.md](docs/setup.md), [docs/local-models.md](docs/local-models.md).

---

## 🏗️ Architecture (in one breath)

Layered **App → Features → Services**, native Swift + SwiftUI + AppKit:

```text
BlitztextMac/
  App/        Lifecycle, paste handling, menu-bar/pill/onboarding/local-models windows, AppState
  Features/   Workflows, menu-bar UI, onboarding, settings, local-model UI
  Services/   Recording, transcription (WhisperKit + OpenAI), the llama.cpp runtime/catalog/download/
              embedding stack, memory (semantic e-mail store, vocabulary, correction mining), hotkeys,
              storage, context capture
  Tests/      XCTest suite for pure logic, Codable migrations, prompts and decisions
docs/         Setup, privacy, local models, roadmap and planning notes
web/          Bilingual marketing + docs website (Next.js, static-exported to GitHub Pages)
```

> Internal type/folder names keep the `Blitztext` prefix on purpose, to keep upstream merges cheap.
> The user-facing brand is **rede**.

---

## 🤝 Contributing

Contributions are welcome — especially anything that makes the project easier to build, understand or
fork. See [CONTRIBUTING.md](CONTRIBUTING.md), [SUPPORT.md](SUPPORT.md) (how to ask without sharing
secrets) and [ROADMAP.md](ROADMAP.md).

## 📄 License & origin

MIT — see [LICENSE](LICENSE); names/logos/icons are not trademarks (see [TRADEMARKS.md](TRADEMARKS.md)).
The bundled runtime is **llama.cpp** by ggml-org; models come from **Hugging Face** under their own
licenses. rede is the standalone, heavily extended spin-off of the original open-source **Blitztext** by
[cmagnussen](https://github.com/cmagnussen/blitztext-app). Impressum & privacy for the website live under
`web/` (`/[locale]/impressum`, `/[locale]/datenschutz`) — fill in real details before a public launch.

<div align="center">

**Made for people who'd rather talk than type — and keep their words on their own machine.**

</div>
