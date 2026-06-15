<div align="center">

# 💬 rede

**A native macOS menu-bar app for dictation, transcription and AI rewriting that runs entirely on your Mac.**

Speak into any text field, get clean text back. Rewrite e-mails, prompts and messages with a local LLM — no cloud, no account, no telemetry. Bring your own OpenAI key only if you _want_ the online path.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Universal](https://img.shields.io/badge/Universal-arm64%20%2B%20x86__64-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)
![Local-first](https://img.shields.io/badge/Local--first-no%20telemetry-brightgreen)
![llama.cpp](https://img.shields.io/badge/Local%20AI-llama.cpp-purple)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

</div>

> **Origin.** rede is the standalone spin-off of the open-source **Blitztext** menu-bar app by
> [cmagnussen](https://github.com/cmagnussen/blitztext-app) (MIT, © Blitztext contributors). It started
> as a simple speech-to-text helper and grew into a full local-AI writing workflow — a bundled
> **llama.cpp** runtime, a dynamic GGUF model catalog with hardware-aware recommendations, semantic
> memory and a redesigned interface. The in-app UI is German by design; the project is documented in
> English. Internal type/folder names keep the `Blitztext` prefix on purpose, to keep upstream merges
> cheap — the user-facing brand is **rede**.
>
> No hosted backend, no warranty, no support guarantee. The point isn't a one-click finished product —
> it's a _hackable_, complete example of how a small native macOS app combines dictation, local models,
> rewrite modes, memory and context. Clone it, build it, read the code, change it.

---

## ✨ Highlights

- 🎙️ **Dictate anywhere** — global hotkey, live recording pill, instant paste into the focused app.
- 🧠 **Rewrite locally** — turn rough speech into clean e-mails, prompts or messages with an on-device LLM.
- 📦 **Bundled llama.cpp runtime** — no separate install, no `ollama pull`, no Docker. The app ships and manages everything.
- 🗂️ **Dynamic model catalog** — curated GGUF models, a **live Hugging Face feed** that auto-discovers new models, and a field to drop in **any `.gguf` URL** yourself.
- 🎯 **Hardware-aware recommendation** — rede reads your RAM and suggests the best model that fits (e.g. _Qwen3-32B_ on a 48 GB Mac, _Qwen3-1.7B_ on an 8 GB Mac).
- 🔒 **Genuinely private** — in local mode nothing leaves the machine. Online calls go straight to OpenAI with _your_ key, stored only in the Keychain.
- ⌨️ **Per-mode hotkeys**, ✍️ **custom modes**, 🧩 **vocabulary learning**, and opt-in **semantic e-mail memory** — all local.

---

## 🌐 Website

**Live:** **[aslomon.github.io/rede](https://aslomon.github.io/rede/)** — a bilingual (DE/EN) marketing +
docs site, source in [`web/`](web/) (Next.js 16, static export to GitHub Pages, mirroring the in-app
design system `DESIGN.md`). It covers the modes, the privacy story, screenshots, a download section and
setup docs, and is auto-deployed from `main` via [`.github/workflows/deploy-web.yml`](.github/workflows/deploy-web.yml).

```bash
cd web && pnpm install && pnpm dev   # → http://localhost:3000
```

Deployment notes (GitHub Pages / Vercel + the Sparkle appcast feed) are in [`web/README.md`](web/README.md).

---

## 📸 Screenshots

|                     Menu bar                      |                        Local models                        |                       Modes                       |
| :-----------------------------------------------: | :--------------------------------------------------------: | :-----------------------------------------------: |
| ![Menu bar popover](docs/screenshots/menubar.png) | ![Local models manager](docs/screenshots/local-models.png) | ![Mode configuration](docs/screenshots/modes.png) |
|       Pick a mode, see its hotkey & backend       |    Install, activate/deactivate & recommend GGUF models    | Tune prompts, tone, memory & enrichment per mode  |

---

## 🧭 What it does

rede lives in the menu bar. Each **mode** is a hotkey that records your voice, transcribes it, and
optionally rewrites it — then pastes the result straight into whatever app you're using. Five fixed
slots, each fully configurable:

| Mode             | Default hotkey      | What it does                                                                            |
| ---------------- | ------------------- | --------------------------------------------------------------------------------------- |
| **Diktat**       | `fn + Shift`        | Pure speech → text via OpenAI. Nothing else.                                            |
| **Diktat lokal** | `fn + Shift + Ctrl` | Speech → text fully on-device with Whisper. No audio leaves your Mac.                   |
| **E-Mail**       | `fn + Ctrl`         | Spoken notes → a clearly structured, ready-to-send e-mail (reads Sie/Du, uses context). |
| **Prompt**       | `fn + Option`       | Dictated task → a precise prompt for AI coding agents like Claude Code or Codex.        |
| **Social**       | `fn + Cmd`          | Spoken text → a social post with tasteful emoji (density adjustable).                   |

Every mode is **fully configurable** — rename it, rebind its hotkey, pick its backend (online/local),
write a custom system prompt, set tone & context, and toggle memory/enrichment. Duplicate a mode to
keep separate setups for different clients or contexts.

---

## 🧠 Local AI — the core of rede

Local rewriting runs on a **bundled [llama.cpp](https://github.com/ggml-org/llama.cpp) server** that the
app starts as a subprocess on `127.0.0.1`. There is **no Ollama and no external runtime** — rede
downloads GGUF model files, verifies them, and runs them itself.

### A model catalog that grows by itself

The **Local Models** window organizes everything in one place — installed models on top
(activate / deactivate / delete), with the full catalog behind a collapsible _"Weitere Modelle laden"_
section. That section has **three sources**:

1. **Curated** — a hand-picked, checksum-pinned set covering every Mac size (Qwen3 · 1.7B–32B, Gemma 3 · 4B–27B).
2. **Live Hugging Face feed** — surfaces the newest GGUFs from trusted orgs automatically, _without an app update_. Junk repos are filtered, oversized models hidden, and the LFS hash is verified on download.
3. **Your own URL** — paste a direct link to any `.gguf` file and download it on the spot.

### It recommends the right model for _your_ Mac

rede reads your chip, RAM and free disk and ranks the catalog by quality _within your budget_. Models
that wouldn't run are hidden; tight-but-usable ones are shown without being recommended.

### Privacy of the local path

- The llama.cpp server binds to `localhost` only, with a per-launch API key.
- Audio is transcribed locally via **WhisperKit / Core ML**; temp audio is deleted after processing.
- Nothing is uploaded, logged or phoned home. Use the app fully offline.

---

## ☁️ Online path (optional)

Set a mode's backend to **Online** and rede uses the **OpenAI API directly** with your own key:

- Transcription via OpenAI Audio Transcriptions (25 MB upload limit, enforced early).
- Rewriting via Chat Completions.
- The key lives **only in the macOS Keychain** — no proxy, no telemetry in between.

You can mix per mode: dictate locally, rewrite online, or the reverse.

---

## 🔄 Updates

The app checks for new versions once a day (and on demand in **Einstellungen → System → Updates**)
against this repository's release feed, powered by [Sparkle](https://sparkle-project.org). Honest scope:
one HTTPS request for the appcast — the user agent carries the app version, nothing else. No system
profile, no identifiers, and the daily check has an off switch. Update archives are EdDSA-signed and
verified before extraction. Details in [docs/privacy.md](docs/privacy.md), release flow in
[docs/release-process.md](docs/release-process.md).

---

## 🧩 Memory, vocabulary & context (all opt-in, all local)

- **Semantic e-mail memory that learns** — opt in, and the more e-mails you dictate, the better it gets. A local vector store (a **nomic-embed-text** GGUF on a second llama.cpp server) embeds your finished drafts and recalls how you phrased _similar cases before_. Capped, retention-aware, never uploaded.
- **Two-variant preview — toggleable** — switch it on per mode and a rewrite pauses in the floating pill with **two versions**; pick the one you like.
- **Vocabulary & term learning** — frequently used names and domain terms are learned and injected into future prompts, with fuzzy correction.
- **Context awareness** — modes can optionally include the focused window, your current text selection, and content-type hints.

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
- For **local AI**: a few GB of free disk per model (~1.3 GB smallest, ~20 GB largest).
- For the **online path**: your own OpenAI API key.
- **Microphone** permission, and **Accessibility** permission for direct paste.

The build pulls one Swift Package automatically: [`argmax-oss-swift`](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) for on-device transcription.

---

## 🛠️ Build & run from source

Requires full **Xcode 16+** and [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The Xcode project is generated from `BlitztextMac/project.yml` — edit that, not the `.xcodeproj`.

```bash
git clone https://github.com/aslomon/rede.git
cd rede

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

For quick UI iteration without the local runtime, build with `--allow-missing-llamacpp-helper` (local
rewrite is then unavailable). The generated `.app` is ad-hoc signed for local development only — a public
release needs Developer ID signing + notarization.

On first launch: grant **Microphone** (and **Accessibility** for direct paste), optionally enter your
**OpenAI key**, and open **Local Models** to download a GGUF model. Slower walkthrough in
[docs/setup.md](docs/setup.md) and [docs/local-models.md](docs/local-models.md).

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
web/          Bilingual marketing + docs website (Next.js 16, Tailwind v4)
build.sh      Local build + signing; scripts/build-llamacpp-helper.sh builds the runtime
docs/         Setup, privacy, local models, roadmap and planning notes
```

Installed models are **self-describing via on-disk manifests**, so curated, Hugging-Face-fetched and
custom-URL models all download, list and run through the same path.

---

## 🤝 Contributing & support

Contributions are welcome — especially anything that makes the project easier to build, understand or
fork. Please read [CONTRIBUTING.md](CONTRIBUTING.md). There's no formal support promise; see
[SUPPORT.md](SUPPORT.md) for how to ask for help without sharing secrets, and [ROADMAP.md](ROADMAP.md)
for direction.

---

## 📄 License

Code is released under the **MIT License** — see [LICENSE](LICENSE). Project names, logos and app icons
are not automatically granted as trademarks; see [TRADEMARKS.md](TRADEMARKS.md).

Local models are downloaded from **Hugging Face** under their respective licenses (Apache-2.0, Gemma
Terms, etc.). The bundled runtime is **llama.cpp** by ggml-org. Based on the original open-source
**Blitztext** by [cmagnussen](https://github.com/cmagnussen/blitztext-app).

## Legal / Impressum & Datenschutz

This is an experimental, non-commercial open-source project, provided as-is under the MIT License
without warranty or support. Impressum and privacy notice for the companion website live under
`web/` (`/[locale]/impressum`, `/[locale]/datenschutz`) — fill in the real provider details before a
public launch.

<div align="center">

**Made for people who'd rather talk than type — and keep their words on their own machine.**

</div>
