# rede — Plan: Konfigurierbare Modi, Offline-LLM & Feature-Ausbau

> Status: **Entwurf / zur Entscheidung**. Erstellt am 2026-06-04 aus einem Multi-Agent-Design-Workflow
> (7 geerdete Feature-Designs → Synthese → adversarisches Scope-Review). Alles baut **additiv** auf dem
> bestehenden Code auf — kein Rewrite. Scope bewusst niedrig gehalten; Phasen 2–3 sind Backlog, nicht Commitment.

---

## 0. Kontext & Sofort-Diagnose (warum es aktuell „nicht geht")

Geprüft an der Laufzeit:

- ✅ OpenAI-Key im Keychain (`app.rede.preview.credentials`), Mikrofon **und** Bedienungshilfen erlaubt.
- ❗️ **`secureLocalModeEnabled = true`** in `~/Library/Application Support/rede/settings.json`.

In `AppState.isWorkflowAvailable` gilt:

```swift
case .textImprover, .dampfAblassen, .emojiText:
    return !appSettings.secureLocalModeEnabled && KeychainService.isConfigured
```

→ Im lokalen Modus sind **alle OpenAI-Umschreib-Modi pausiert** und Transkription läuft lokal. Genau die
Funktionen (E-Mail/Prompt formulieren über OpenAI), die gebraucht werden, sind dadurch aus.

**Sofort-Quickwin (kein Build):** App beenden → in `settings.json` `secureLocalModeEnabled=false` setzen +
`customName`/`systemPrompt` für die beiden Umschreib-Modi setzen → App neu starten. Liefert sofort funktionierende
E-Mail-/Prompt-Modi inkl. zweier Umbenennungen. Der „normale" Modus (`transcription`) lässt sich so **nicht**
umbenennen (Name fest im Enum) — dafür braucht es Phase 1.

---

## 1. Das Muster (die 4 Kern-Abstraktionen)

Alles unten Stehende komponiert über genau diese vier additiven Bausteine:

### 1) Mode-Modell (das Rückgrat)

Die fixe 5-Slot-`WorkflowType`-Enum **bleibt** (sie ist die Identität für Hotkeys, MenuBarStatus, Paste-Targeting
und die `as?`-Downcasts in `MenuBarView`). Darüber liegt ein konfigurierbarer Wert pro Slot:

```swift
enum ModeKind: String, Codable { case transcribeOnly, transcribeThenRewrite, transcribeThenEmoji } // gespeichert, vorerst nicht editierbar
enum RewriteBackend: String, Codable { case openai, appleIntelligence }
enum ReplyContextMode: String, Codable { case off, replyUsingContext, editSelection }

struct RewriteConfig: Codable {
    var systemPrompt = ""
    var rewriteBackend: RewriteBackend = .openai
    var modelID = "gpt-4o"            // String → Registry darf sich entwickeln
    var tone: TextImprovementSettings.TextTone = .neutral
    var context = ""
    var emojiDensity: EmojiTextSettings.EmojiDensity = .mittel
    var replyContextMode: ReplyContextMode = .off
}

struct ModeConfig: Codable, Identifiable {
    var slot: WorkflowType
    var id: String { slot.rawValue }
    var userName = ""                 // Umbenennen
    var isEnabled = true              // Aktiv/Aus
    var kind: ModeKind
    var rewrite = RewriteConfig()
}
```

- Speicher: `AppSettings.modes: [String: ModeConfig]` **keyed by `WorkflowType.rawValue`** (String-Key — siehe
  Risiko „JSON-Dictionary-Falle"). `var modesSchemaVersion = 1` für spätere Feldänderungen.
- `customTerms` bleiben **global** (sind heute schon geteilt → Whisper-Prompt + LLM-Prompt), nicht in `RewriteConfig` dupliziert.
- `AppState`: `modeConfig(for:) -> ModeConfig` (Fallback `.default(for:)`) + `modeBinding(for:) -> Binding<ModeConfig>`.
  `displayName(for:)`, `isWorkflowAvailable(_:)`, `startWorkflow` lesen aus `ModeConfig`.

### 2) Rewrite-Provider-Seam (spiegelt das vorhandene `TranscriptionBackend{remote,local}`)

```swift
protocol RewriteProvider: Sendable {
    func rewrite(systemPrompt: String, userText: String, temperature: Double?) async throws -> String
    static func isReady() -> Bool
}
```

- `LLMService` wird zur **Fassade**. `buildSystemPrompt`/`buildEmojiSystemPrompt` bleiben **unverändert**
  (der wertvolle, provider-agnostische Teil). Der OpenAI-HTTP-Body wandert 1:1 in `OpenAIRewriteProvider`.
- `FoundationModelsRewriteProvider` gegated `@available(macOS 26.0, *)` (Apple on-device LLM).
- `AppState.rewriteProvider(for:)` = Factory; die 3 Umschreib-Workflows bekommen einen `rewriteProvider`-Parameter
  (Default OpenAI für Source-Kompatibilität). **Prompt-Bau wird nie verschoben.**

### 3) Modell-Registry (für den OpenAI-Provider)

```swift
struct RewriteModelOption { let id, label, tier, goodFor: String; let supportsTemperature: Bool }
```

- Persistiert nur `RewriteConfig.modelID: String`; unbekannte IDs fallen zur Laufzeit auf einen Default zurück.
- `OpenAIChatRequest.temperature` wird **optional** und bei `supportsTemperature == false` weggelassen
  (neuere Reasoning-Modelle lehnen `temperature` per 400 ab).
- **Defaults = nur real existierende IDs** (`gpt-4o`, `gpt-4o-mini`). Neuere Modelle erst als Opt-in, **nachdem**
  die exakte ID gegen die OpenAI-API verifiziert ist (siehe Review-Flag).

### 4) Capture-/Context-Hooks (additive Punkte am `Workflow`-Protokoll, alle default-nil → 0 Kosten wenn ungenutzt)

- `onArchiveCapture: ((URL?, Double) -> Void)?` — in `stop()` **nach** dem Quality-Gate und **vor** dem Löschen
  der Audiodatei (Archiv kopiert hier).
- `onRawTranscript: WorkflowOutputHandler?` — neben `onOutput`, trägt das Roh-Transkript für Archiv + Vokabular.
- `SelectionContext` — synchron in `startWorkflow` direkt nach `activePasteTarget = …` erfasst (App noch im Vordergrund).
- Master-Privacy-Schalter: `secureLocalModeEnabled` → **`forceOfflineMode`** umbenennen (Legacy-Key als Fallback
  dekodieren). Statt Umschreib-Modi zu _deaktivieren_, **erzwingt** er für jeden Modus die lokalen Backends.

**Warum das komponiert:** `ModeConfig.rewrite` ist der **eine** Ort für Backend, Modell, Prompt, Ton, Reply-Kontext.
Der Provider-Seam macht das lokale LLM zu einem 2-Methoden-Conformer. Die Capture-Hooks teilen sich Archiv + Vokabular
und fassen den Aufnahme-/Paste-Hot-Path nie an. Alles persistiert über den einen JSON-Container mit `decodeIfPresent`.

---

## 2. Phasen-Roadmap

> **Empfehlung des Reviews:** _Verbindlich_ nur Phase 1. Phase 2 deckt die ausdrücklich gewünschte Offline-Fähigkeit
> ab (daher hoch priorisiert), Phase 3 ist echtes Backlog. Phasen sind unabhängig auslieferbar.

### Phase 0 — Voraussetzungen (klein, aber Pflicht)

- **`DESIGN.md`** anlegen (laut globaler Regel zwingend vor UI-Arbeit) — bestehende Settings-Bildsprache festhalten
  (11pt sekundäre `SectionLabel`s, Capsule-Chips, `SubtleButtonStyle`, 6pt-Radien).
- **XCTest-Target** in `project.yml` ergänzen + `xcodegen generate` (es existiert **kein** Test-Target — sonst sind
  alle „Unit-Test"-Deliverables Luft).
- Merke: nach jedem neuen File `xcodegen generate` laufen lassen und das `.xcodeproj` neu erzeugen.

### Phase 1 — Mode-Fundament + Umbenennen + OpenAI-Modell pro Modus (MVP) · Aufwand **L**

Das Kern-Feature und die Schlagzeile-Wünsche.

- `WorkflowProtocol.swift`: `ModeKind`, `RewriteBackend`, `ReplyContextMode`, `RewriteConfig`, `ModeConfig` +
  `ModeConfig.default(for:)` mit defaultender `init(from:)`.
- `AppSettings`: `modes: [String: ModeConfig] = [:]`, `didMigrateToModeConfigs = false`, `modesSchemaVersion = 1`
  (+ `CodingKeys` + `decodeIfPresent` analog WorkflowProtocol.swift:148-161). **JSON-Round-Trip-Test** der `modes`.
- `RewriteModelRegistry.swift`: kuratierte Liste (**echte** IDs: `gpt-4o-mini`, `gpt-4o`), `option(for:)` + Fallback,
  `supportsTemperature`; `OpenAIChatRequest.temperature` → optional; Retry-einmal bei „model not found".
- `AppState`: `modeConfig(for:)`, `modeBinding(for:)`, **einmalige** `migrateToModeConfigsIfNeeded()` in `init`
  (gegated per Flag) — liest **alle fünf** bereits geladenen Legacy-Settings und ruft **explizit `saveSettings()`**
  auf (⚠️ `didSet` feuert in `init` **nicht**). `displayName(for:)` liest `userName` für **alle** Slots;
  `isWorkflowAvailable` bekommt `isEnabled`-Guard; `startWorkflow` reicht das aufgelöste `RewriteConfig` + `modelID`
  in die 3 Umschreib-Workflow-Inits (alte Parameter defaulted lassen).
- `LLMService`: `improve/dampfAblassen/addEmojis` akzeptieren `modelID: String` (über Registry aufgelöst);
  Prompt-Bau unverändert.
- `CustomizeSettingsView`: pro Modus **„Name"-TextField + „Aktiv"-Toggle + „Modell"-Picker** (gebunden via
  `modeBinding(for:)`); vorhandene Ton/Prompt/Kontext/Density-Bindings auf `modeConfig.rewrite.*` umhängen.
  **„Auf Standard zurücksetzen"**-Knopf pro Modus (Recovery bei kaputtem Prompt).
- Test: Migration kopiert alle Legacy-Felder; JSON-Round-Trip von `AppSettings.modes` (exakte Shape asserten).

**Ergebnis:** Umbenennen, eigener Prompt pro Modus, Modellwahl pro Modus, Aktiv/Aus — bei
byte-kompatibler alter `settings.json` und **null** Änderung an Hotkey-/Status-Plumbing.

### Phase 2 — Provider-Seam + Offline-Rewrite (Apple FM) + markierter-Text-Kontext · Aufwand **L**

Deckt den ausdrücklichen Offline-Wunsch (Qwen/Gemma-Klasse) ab.

- `Services/Providers/RewriteProvider.swift` (Protokoll); `LLMService` → Fassade; OpenAI-Body 1:1 in
  `OpenAIRewriteProvider` (`isReady == KeychainService.isConfigured`).
- `FoundationModelsRewriteProvider.swift` `@available(macOS 26.0, *)` — Verfügbarkeit über
  `SystemLanguageModel.default.availability`; **Deployment-Target bleibt 14.0**, alles weak-gegated; freundliche
  Fehler für „Apple Intelligence aus / Gerät nicht geeignet".
- `secureLocalModeEnabled` → **`forceOfflineMode`** (Legacy-Fallback); `resolvedRewriteBackend(for:)` zentral
  (⚠️ **~22** Lese-Stellen müssen über den Resolver laufen). `isWorkflowAvailable` ist offline true, wenn der
  gewählte Offline-Provider bereit ist; `workflowSubtitle` sagt nicht mehr „Im lokalen Modus pausiert".
- `SelectionContextService.swift`: AX-Read (`kAXSelectedText` / Umfeld `kAXValue`+`kAXSelectedTextRange`, Char-Caps
  ~4000/~1500), nur im Speicher, **nie persistiert**; synchron in `startWorkflow` erfasst, überall mit
  `activePasteTarget` geleert. `ReplyContextMode` injiziert einen abgegrenzten Kontextblock in den System-Prompt —
  **nur** für rede+, Default `.off`, mit Privacy-Hinweis (markierter Text geht an OpenAI, außer offline).

### Phase 3 — Privacy-Archiv + On-Device-Vokabular-Lernen (Backlog) · Aufwand **XL**

Die schwereren Opt-in-Datenfeatures zuletzt; default **AUS**, Daten nur mit explizitem Consent auf Platte.

- `Workflow`-Protokoll: default-nil `onArchiveCapture/onRawTranscript` Hooks; verdrahtet **nur** bei `archive.isEnabled`.
  Audio **synchron in `stop()` kopieren, BEVOR** `TranscriptionService.transcribe` (hat eigenes `defer removeItem`)
  und der Workflow-`defer` die Datei löschen (⚠️ Doppel-Delete-Race).
- Archiv: `index.json` (Codable) + lose `m4a` nach Jahr/Monat (kein GRDB/SQLite); `ArchiveRetentionSweeper`
  (90-Tage-Rolling + Größen-Cap); `ArchiveView` + `AudioPlayerView` (neue `.archive`-Page); POSIX 0600.
- Vokabular: `TranscriptHistoryStore` (Text-Ringpuffer, gegated) + `VocabularyExtractionService`
  (NLTagger-NER + NSSpellChecker-Seltenheit + DE/EN-Stoppliste + Frequenz) → **nutzerbestätigte** Vorschlags-Chips
  → bestehende `customTerms` (nie auto-add; Listenlänge cappen wegen ~224-Token-Whisper-Budget).
- Optional Phase B: Transkriptions-Modell-Picker (`gpt-4o-transcribe` mit `response_format=json` vs `whisper-1`).

---

## 3. Bewusste Scope-Cuts (was wir NICHT bauen)

- ❌ **Option B** (echte frei definierbare Modus-Liste mit UUID) — würde `WorkflowType`-Identität durch
  `HotkeyEvent`/`MenuBarStatus`/Paste/Downcasts brechen → Quasi-Rewrite. Fixe 5 Slots + `ModeConfig` reicht.
- ❌ **MLX / llama.cpp** fürs Offline-LLM — schwere SPM-Dep + zweiter Modell-Download + RAM/Binary-Kosten.
  **Apple Foundation Models** ist zero-dependency, zero-download, Deutsch unterstützt und benchmarkt vor Qwen-2.5-3B.
  **Ollama** nur als Fast-Follow für Pre-macOS-26-/ungeeignete Macs.
- ❌ `ModeKind` **nicht** user-editierbar in Phase 1–2 (würde MenuBarView-Downcasts invalidieren) — nur gespeichert.
- ❌ Verschlüsselung-at-Rest fürs Archiv (bricht direkte `AVAudioPlayer`-Wiedergabe) → spätere Opt-in-Phase.
- ❌ `editSelection`-Variante + Clipboard-Cmd+C-Fallback (zerstört Zwischenablage, Race mit unserem Paste).
- ❌ Spekulative `gpt-5.x`-IDs als Shipping-Default.

---

## 4. Risiken & Pflicht-Checks (aus dem adversarischen Review)

1. **JSON-Dictionary-Falle:** `JSONEncoder` kodiert Dicts mit Nicht-String-Keys als **Array**. → `modes` als
   `[String: ModeConfig]` (rawValue) + Round-Trip-Test, der die exakte Shape asserted.
2. **Migrations-Bug:** `didSet` feuert in `init` **nicht** → Migration muss `saveSettings()` **explizit** rufen,
   sonst wird nie persistiert und re-migriert jeden Start. Vor jedem View-Binding in `init` laufen, Flag setzen.
3. **Deployment-Target-Mismatch:** App-Target 14.0, FoundationModels 26.0 → **jede** FM-Referenz hinter
   `@available/#available`. `project.yml` bei 14.0 lassen, nur Runtime-Gate.
4. **Apple-Intelligence-Verfügbarkeit** ist dreifach bedingt (macOS 26 + geeignetes Apple Silicon + nutzeraktiviert)
   → alle drei Unavailable-Gründe anzeigen + Fallback. **FM-Safety-Filter** beim „Dampf ablassen"-Modus real testen.
5. **Privacy-Egress-Falle:** lokale Transkription + Remote-Rewrite (oder Reply-Kontext) sendet sensible Texte an
   OpenAI. `forceOfflineMode` MUSS jedes Backend hart auf lokal überschreiben; Reply-Kontext default `.off` + Caption.
6. **Archiv-Privacy-Regression:** Hooks nur bei `archive.isEnabled`; Audio **vor** dem `defer removeItem` kopieren.
7. **Model-IDs:** Defaults = real (`gpt-4o`/`gpt-4o-mini`); neuere IDs erst nach Verifikation gegen die API.
8. **Fehlende Infra:** kein Test-Target, keine `DESIGN.md` → Phase 0.
9. **AX-Realität:** `kAXSelectedText` ist in WebKit/Electron-Mail-Clients (Web-Gmail, Spark, viele Outlooks) oft
   **nicht** verfügbar → echte Trefferquote im genutzten Mail-Client unsicher; still auf heutiges Replace zurückfallen.

---

## 5. Offene Entscheidungen (vor Phase 1)

1. **Modus-Namen** — z. B. `Diktat` / `E-Mail` / `Prompt` (+ Emoji-Modus behalten oder zweckentfremden?).
2. **OpenAI-Modelle** — vorerst nur bewährt (`gpt-4o`/`gpt-4o-mini`), oder neuere Modelle gleich verdrahten
   (exakte IDs verifiziere ich gegen deinen Account)?
3. **Umfang/Start** — nur Phase 1 jetzt, oder Phase 1 **und** 2 (Offline) zusammen?
4. **Offline-Erzwingen** — soll `forceOfflineMode` (an) automatisch Apple FM fürs Umschreiben wählen, oder Backend
   pro Modus unabhängig und nur hart auf lokal cappen? (Empfehlung: hart cappen, FM auto-wählen wenn vorhanden.)
5. **Reply-Kontext** — nur rede+ zuerst, oder auch „Dampf ablassen" (ruhig auf wütende Mail antworten)?

---

## 6. Quellen

- Workflow-Lauf `wf_c1868e86-dc2` (9 Agenten, ~750k Tokens): 7 Feature-Designs, Synthese, Scope-Review.
- ROADMAP-Bestätigung: „provider boundaries so OpenAI and future local transcription can be swapped more cleanly",
  „Prototype local transcription with WhisperKit or whisper.cpp".
- Geprüfte Dateien: `WorkflowProtocol.swift`, `AppState.swift`, `LLMService.swift`, `HotkeyService.swift`,
  `SettingsContentView.swift`, `KeychainService.swift`, `TextImprovementWorkflow.swift`, `TranscriptionService.swift`.
