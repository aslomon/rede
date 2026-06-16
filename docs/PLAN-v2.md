# rede — Plan v2 (Lokales LLM, Anpassen-Redesign, Signatur-Fix, Transkriptions-Archiv & Memory)

> Status: **Entwurf / zur Entscheidung**, 2026-06-04. Baut additiv auf dem ausgelieferten Phase 1+2 auf
> (ModeConfig, RewriteProvider-Seam, `secureLocalModeEnabled` als Offline-Master). Kein Rewrite.
> Aus Multi-Agent-Workflow (4 Designs + Synthese + adversarisches Scope-Review) + Nutzer-Korrektur zu Feature 4.

---

## Vier Bereiche (nach Wert + Risiko geordnet)

| #   | Phase                                           | Aufwand | Kern                                          |
| --- | ----------------------------------------------- | ------- | --------------------------------------------- |
| 1   | **Signatur + Bedienungshilfen-Fix** (Unblocker) | M       | TCC-Freigaben überleben Rebuilds              |
| 2   | **„Anpassen"-Redesign + „Lokal"-Umbenennung**   | M       | „Zu breit" beheben; Apple-Branding raus       |
| 3   | **Lokales LLM Gemma/Qwen (MLX)** — Headline     | L       | Echte herunterladbare Offline-Modelle         |
| 4   | **Transkriptions-Archiv + Memory**              | L–XL    | 90 Tage + strukturierter Kontext für die Modi |

---

## Phase 1 — Stabile Signatur + Bedienungshilfen-Erkennung (der Unblocker) · M

**Ursache (bestätigt):** `build.sh` signiert **ad-hoc** (`codesign --sign -`). Jeder Rebuild erzeugt einen neuen
CDHash → macOS-TCC hat die Freigabe gegen den **alten** Code-Requirement gespeichert → `AXIsProcessTrusted()`
liefert `false`, obwohl der Toggle in den Systemeinstellungen „an" aussieht.

- **`scripts/create-dev-cert.sh`** (idempotent): selbst-signiertes Code-Signing-Zertifikat „rede Local Dev"
  per `openssl` (extendedKeyUsage=critical,codeSigning) → `pkcs12 -legacy` → `security import` in den Login-Keychain
  mit `-T /usr/bin/codesign`. Verifikation per Wegwerf-Test-Signatur (nicht `find-identity`). **Kein bezahlter
  Apple-Developer-Account nötig.**
- **`build.sh`**: `CODESIGN_IDENTITY="rede Local Dev"`; beide `codesign --force --sign -` (Zeilen 142, 158)
  → `--force --options runtime --entitlements Resources/RedeMac.entitlements --sign "$CODESIGN_IDENTITY"`.
  Danach **Assert**: `codesign -d -r-` muss `certificate leaf` (nicht `cdhash`) enthalten — sonst laut abbrechen,
  kein stiller Ad-hoc-Fallback.
- **Einmalig** beim ersten stabilen Build: alten „rede"-Eintrag unter Bedienungshilfen/Mikrofon/
  Eingabeüberwachung entfernen (`–`) und neu hinzufügen. Danach bleiben Freigaben über Rebuilds erhalten.
- **In-App** (`AccessibilityPermissionService` + `AppState` + `AccessSettingsView`): `AXIsProcessTrusted()`
  bei App-Aktivierung/Popover-Öffnen erneut prüfen (bounded Poll ~10s statt der fixen 1s/3s-`asyncAfter`),
  Status „erkannt / nicht erkannt", und **Stale-Grant-Erkennung** (`hadAccessibilityGrant` persistiert →
  wenn früher erlaubt, jetzt `false` → gezielter Hinweis „einmal entfernen + neu hinzufügen").

> ✅ Review: „strongest part of the plan", voll verifiziert auf dieser Maschine. **Kein** In-App-`tccutil reset`
> (mutiert System-Privacy) — bleibt manueller, dokumentierter Schritt.

---

## Phase 2 — „Anpassen"-Redesign (Picker-Overflow) + „Lokal"-Umbenennung · M

**Problem:** Im 340pt-Popover sind segmentierte Picker mit langen Labels („Online (OpenAI)" / „Lokal (Apple)")
und mehrere volle Breite-Controls zu breit.

- **Picker-Fix:** `backendPicker` (und ggf. `replyContextPicker`) in `ModeCardView` von `.segmented` auf
  **Menu-Picker** (`.controlSize(.small)`) umstellen. Ton + Emoji-Dichte bleiben segmentiert (kurze Labels).
  ⚠️ **Korrektur aus Review:** DESIGN.md sagt aktuell „.segmented für 2–3 Optionen" — Backend hat genau 2, ist
  also formal _konform_. Der Swap ist trotzdem die richtige UX → **zuerst DESIGN.md-Regel anpassen**
  (Anzahl _oder_ Label-Breite), dann der Swap ist sauber.
- **Kompaktere Karte:** `LabeledRow`-Helfer (Label rechtsbündig + Control füllt Rest) für Name/Verarbeitung/Modell;
  Qualifier ins Caption (z. B. „Kontext", Hinweis als `.help`). _(Optional — siehe Scope-Cut.)_
- **Modus-Auswahl:** statt 3 gestapelter Karten ein **kompakter Modus-Picker** oben (E-Mail/Prompt/Social), der
  **eine** Karte zur Zeit zeigt — volle vertikale Fläche, kein neues Fenster. _(Optional — siehe Scope-Cut.)_
- **„Lokal"-Umbenennung (Vorarbeit für Phase 3):** `RewriteBackend.appleIntelligence` → **`.local`**
  (Label „Lokal", alle „Apple Intelligence"/„Apple"-Strings raus, auch in `FoundationModelsRewriteProvider`-Fehlern).
  Legacy-Migration: custom `Decodable` für `RewriteBackend` mappt altes Rohwort `"appleIntelligence"` → `.local`,
  damit bestehende `settings.json` weiter laden. `hasMigratedRewriteBackendToLocal`-Flag.

> ⚠️ **Kein** dediziertes Settings-Fenster (NavigationSplitView) — die App ist menüleisten-only (`LSUIElement`),
> ein echtes Fenster bekämpft die `.accessory`-Activation-Policy. Der Picker-Swap löst das gemeldete Problem.
> ⚠️ **Kein Test-Harness vorhanden** → die Rename-Migration mit **einem echten Round-Trip-Test** absichern (neu anlegen).

---

## Phase 3 — Lokales LLM: Gemma / Qwen via MLX (Headline) · L · **Risiko-Phase**

Echter herunterladbarer On-Device-LLM-Pfad fürs Umschreiben, überall nur **„Lokal"**.

- **Runtime: MLX Swift** (`ml-explore/mlx-swift-lm`: `MLXLLM` + `MLXLMCommon` + `MLXHuggingFace`) — Swift-nativ,
  lädt offizielle `mlx-community`-Quants von Hugging Face, **spiegelt exakt** den ausgelieferten WhisperKit-
  Download/Install/Prepare-Flow (`LocalTranscriptionService` + `installSelectedLocalModel`). Kein externer Daemon.
- **Modelle (kuratierter Picker, GLOBAL wie das WhisperKit-Modell):**
  - **Default (entschieden):** `mlx-community/gemma-4-e4b-it-8bit` (~9 GB, ~8 GB RAM) — beste Qualität. Größe + RAM werden vor dem Download deutlich angezeigt.
  - **„Schlanker":** `mlx-community/gemma-4-e4b-it-4bit` (~2,5 GB, ~5 GB RAM).
  - **Qwen-Alternative:** `mlx-community/Qwen3.5-4B-MLX-4bit` (~2,9 GB).
  - _(Exakte Repo-IDs + Größen zur Implementierungszeit erneut verifizieren.)_
- **Neue Bausteine:** `LocalLLMService` (Actor, analog `LocalTranscriptionService`: Modell-Liste, Download/
  Install/Progress, gecachter `ModelContainer`, Speicher unter `Application Support/rede/models/llm/`),
  `LocalLLMRewriteProvider: RewriteProvider` (`ChatSession(container, instructions: systemPrompt).respond(to:)`).
  Prompt-Bau bleibt in `LLMService`.
- **Factory:** `rewriteProvider(.local)` → MLX-Provider wenn Modell installiert; sonst auf macOS 26
  `FoundationModelsRewriteProvider` als **versteckter** Zero-Download-Fallback (nie „Apple" genannt); sonst
  `UnavailableRewriteProvider("Lade zuerst ein lokales Modell.")`.
- **SPM:** `project.yml` um `mlx-swift-lm` (+ `swift-huggingface`, `swift-transformers`) erweitern.

> 🔴 **Build-Entscheidung (getroffen): arm64-only.** Das Universal-Binary wird aufgegeben, da MLX Apple-Silicon-only
> ist. `build.sh`/`verify_universal_app` werden von `arm64 x86_64` auf **`arm64`** umgestellt.
> Verbleibendes Risiko: mögliche **SPM-Versionskollision** mit `swift-transformers` (schon via ArgmaxOSS/WhisperKit).
> → **Phase 3 startet mit einem Spike**, erste Aufgabe: „Löst `mlx-swift-lm` neben ArgmaxOSS 0.18.0 auf und entsteht
> ein signierbares arm64-Binary?" Erst nach grünem Gate die Integration committen.

---

## Phase 4 — Transkriptions-Archiv + Memory (KORRIGIERT nach deiner Klärung) · L–XL

**Das meinst du** (nicht eine Prompt-Übersicht): ein **Transkriptions-Archiv** plus eine daraus **automatisch
generierte, strukturierte Memory**, die den Modi **immer als Kontext** mitgegeben wird.

> **Umsetzungsreihenfolge (entschieden): Text + Memory zuerst (4a + 4b), Audio-Aufnahmen + Wiedergabe später (4c).**

### 4a — Transkriptions-Archiv (90 Tage, Text zuerst)

- Speichert pro Lauf: Datum, Modus, Dauer, **Roh-Transkript** + Endtext + Backend. _(Audio kommt in 4c.)_
- **Nach Tagen browsbar**: alle Transkriptionen der letzten 90 Tage ansehen, Roh- vs. Endtext sehen.
- Speicher unter `Application Support/rede/archive/` (`history.json`), POSIX 0600.
  **Opt-in, default AUS** (Privacy-Default „nichts wird gespeichert" bleibt, bis du aktivierst).
- Hook: `onRun` am `Workflow`-Protokoll (default-nil, nur bei aktiviertem Archiv verdrahtet) — Text only, kein Audio.

### 4c — Audio-Aufnahmen + Wiedergabe (späterer Schritt)

- Aufnahmen mitspeichern (Audio **vor** dem `defer removeItem` kopieren, nach Tag, POSIX 0600) + Player-UI;
  Retention/Größen-Cap. Eigene Opt-in-Stufe, da deutlich speicher- und privacy-intensiver.

### 4b — Memory (strukturierter, persönlicher Sprachkontext)

- Aus den 90 Tagen Transkripten **on-device** ableiten (Apple `NaturalLanguage` NLTagger + Häufigkeit/Seltenheit):
  - **Namen / Eigennamen** (NER)
  - **Fremdwörter** (Out-of-Dictionary / Seltenheit ggü. DE/EN-Wortliste)
  - **Fachbegriffe / wiederkehrende Terminologie** (Häufigkeit)
- **Strukturiert** als kuratierbare Memory (du kannst bestätigen/bearbeiten/entfernen — nie blind auto-übernommen).
- **Zwei Wirkungen:**
  1. **Erkennung:** Memory-Begriffe fließen in die **Whisper-Vokabel-Hinweise** (`customTerms`) → Namen/Fremdwörter
     werden beim Diktieren korrekt erkannt (alle Modi).
  2. **Formulierung:** Eine **strukturierte Kontext-Block** wird in den Rewrite-System-Prompt der **Modi** injiziert,
     z. B.:
     ```
     [Persönliches Vokabular — exakt so schreiben]
     Namen: …
     Fachbegriffe: …
     Fremdwörter: …
     ```
- **Steuerung:** globaler Schalter **„Memory als Kontext nutzen"** + **pro Modus** ein Toggle
  (`ModeConfig.rewrite.useMemoryContext`). Gilt für die **Modi** (E-Mail/Prompt/Social), **nicht** zwingend für das
  reine Diktat — genau wie von dir beschrieben („nicht bei der Transkription muss es sein, aber bei den Modis an und global").

#### Memory-Mechanik (verbindlich) — Detailspez: `docs/MEMORY-spezifikation.md`

- **Zwei Geschwindigkeiten:** „Kandidaten berechnen" (häufig, billig, Hintergrund) ist getrennt von „injizierte
  Memory" (stabil, ändert sich **nur** bei deiner Bestätigung/Bearbeitung). Verhindert Prompt-Churn & sichert Vertrauen.
- **Update-Takt:** **ereignisgesteuert + debounced + im Hintergrund** — inkrementelles Fold pro Lauf (`onRun`,
  `Task.detached(.utility)`, **kein** 90-Tage-Rescan), debounced Idle-Refresh (~60–120 s nach Burst), App-Start-Catch-up
  (mtime-gated), **1×/Tag** Decay/Prune. Injektion ändert sich nie als Nebeneffekt.
- **Extraktion** aus dem **Roh-Transkript** (nicht dem Endtext); **Frequenz × Seltenheit**, gegated auf
  Out-of-Dictionary/Eigennamen (nicht NER-gated — deutsche NER überfeuert); persistenter Kandidaten-Index.
- **Datenmodell** (`memory.json`, separat, 0600, opt-in): `candidates` / `confirmed` (→ Injektion) / `denylist`
  (entfernte Begriffe kommen nie zurück) / `lastProcessed`.
- **Injektion gedeckelt:** Whisper-Hinweis **~50–60 Begriffe / ≤180 Tokens**, beste **zuletzt** (224-Token-Budget,
  Whisper droppt die frühesten); Namen+Fremdwörter vor Fachbegriffen. LLM-Block als Schreibweisen-Hinweis, nicht „benutze diese Wörter".

### UI

- Neuer **„Archiv"-Tab/Seite**: Tagesliste (Transkript + Aufnahme abspielen) · Memory-Sektion
  (Namen/Fachbegriffe/Fremdwörter, editierbar, bestätigen/entfernen) · Retention/„Archiv löschen".
- Globaler Memory-Schalter dort; Pro-Modus-Toggle in den Modus-Karten (Phase 2/3-UI).

> Privacy: opt-in, default aus, 100% on-device (NaturalLanguage + Zähler), purgeable. **Text-zuerst möglich:**
> Memory aus Transkripten + Kontext-Injektion zuerst, Audio-Aufnahmen/Wiedergabe als zweiter Schritt (siehe Entscheidung).

---

## Bewusste Scope-Cuts

- ❌ Dediziertes Settings-**Fenster** (NavigationSplitView) — Popover-Picker-Swap reicht.
- ❌ **Pro-Modus** lokales LLM-Modell — global (ein Modell), wie WhisperKit; weniger RAM-Churn.
- ❌ Große Modelle (Gemma-12B ~11 GB, Qwen-9B) im ersten Wurf — überraschende Riesen-Downloads.
- ❌ Ollama / llama.cpp — nur MLX spiegelt die In-App-Download-UX.
- ❌ In-App `tccutil reset` — manueller Schritt.
- ⚠️ Optionale Phase-2-Umbauten (LabeledRow, Ein-Karte-Auswahl) — nur falls der reine Picker-Swap nicht reicht.

## Risiken

1. **MLX × Universal-Binary**: arm64-only-Fallback realistisch (Spike entscheidet).
2. **SPM-Kollision** `swift-transformers` (MLX vs. ArgmaxOSS) — im Spike zuerst prüfen.
3. **Kein Test-Harness** → Rename- + Settings-Migrationen mit echtem Round-Trip-Test absichern.
4. **Archiv = erster persistenter Audio-/Transkript-Speicher** → strikt opt-in, 0600, purgeable, klar kommuniziert.
5. **Rename `.appleIntelligence`→`.local`** ist ein breiter mechanischer Switch-Change (Legacy-Decode schützt Daten).

## Empfohlene Reihenfolge (Review)

**Sofort sicher:** Phase 1 (Unblocker) + der 2-Zeilen-Picker-Swap aus Phase 2 + die „Lokal"-Umbenennung.
**Dann:** Phase 3 als Spike → bei grünem Gate die Gemma/Qwen-Integration. **Dann:** Phase 4 (Archiv text-first → Memory → Audio).

## Entschieden (2026-06-04)

1. **Default lokales Modell:** **Gemma 8-bit (~9 GB)** als Standard (beste Qualität). 4-bit + Qwen 3.5 4-bit bleiben im Picker. Braucht ~8 GB RAM + ~9 GB Speicher — wird vor dem Download deutlich angezeigt.
2. **Build-Ziel:** **arm64-only** — Universal wird aufgegeben (Intel-Macs entfallen; auf M3 Max irrelevant). `verify_universal_app` in `build.sh` wird auf arm64 umgestellt.
3. **Apple Foundation Models:** bleibt als **versteckter, nie als „Apple" bezeichneter** Zero-Download-Fallback (offline funktioniert vor dem ersten MLX-Download). Empfehlung beibehalten — sag Bescheid, wenn ganz raus.
4. **Archiv:** **Text + Memory zuerst** (Transkripte + strukturierte Memory + Kontext-Injektion), **Audio-Aufnahmen + Wiedergabe später** als eigener Schritt.
5. **Reihenfolge / Umsetzung:** **Vorerst nur der Plan — noch nicht bauen.** Umsetzung später separat freigeben.

> Wenn gebaut wird, empfiehlt das Review: Phase 1 (Unblocker) + Picker-Swap + „Lokal"-Rename zuerst, dann
> Phase 3 als Spike (arm64-only, Gemma-8-bit), dann Phase 4 (Text/Memory → später Audio).
