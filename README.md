<div align="center">

# rede

**Sprich. Es wird Text. Auf deinem Mac, für deinen Mac.**

rede ist eine native macOS-Menüleisten-App für Diktat, Transkription und KI-Umschreiben —
local-first, ohne Konto, ohne Telemetrie.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Universal](https://img.shields.io/badge/Universal-arm64%20%2B%20x86__64-blue)
![Local-first](https://img.shields.io/badge/Local--first-no%20telemetry-brightgreen)

</div>

> **Herkunft.** rede basiert auf dem Open-Source-Projekt
> [Blitztext](https://github.com/aslomon/blitztext-app) (MIT License, © Blitztext contributors)
> und führt es als eigenständiges Produkt weiter. Der vollständige Lizenzhinweis liegt in der App
> unter Einstellungen → System → Über & Lizenzen sowie in `LICENSE`.

## Was rede kann

- 🎙️ **Überall diktieren** — globaler Hotkey, schwebende Aufnahme-Pille, direktes Einfügen.
- 🧠 **Lokal umschreiben** — gesprochene Gedanken werden saubere E-Mails, Prompts, Nachrichten;
  ein gebündeltes llama.cpp-Runtime führt GGUF-Modelle direkt auf dem Mac aus.
- 🔒 **Ehrlich privat** — im lokalen Modus verlässt nichts den Rechner. Der Online-Pfad (optional)
  geht direkt zu OpenAI mit deinem eigenen Schlüssel aus dem Keychain.
- 🔄 **Updates mit Augenmaß** — täglicher Check gegen den Release-Feed, EdDSA-signiert,
  abschaltbar, ohne Profildaten.

## Build

Wie beim Upstream-Projekt: XcodeGen + Xcode 16, `./build.sh --debug`, Tests via `./test.sh`.
Details in `agent.md`.

## Status

Eigenständige Weiterentwicklung in Richtung Direktvertrieb (notarisiert) und Mac App Store —
siehe `docs/PLAN-updates-and-distribution.md` und `docs/app-store-runbook.md`.
