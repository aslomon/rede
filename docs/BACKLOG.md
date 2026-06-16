# rede — Autonomous Development Backlog

Source of truth for the autonomous improvement loop. Each completed phase spawns 3 reflection
agents (deeper-research / new-features / UX-review) whose ideas land here; each iteration picks the
highest-value `todo` item, implements + verifies (build + tests + review), installs, then reflects.

**Legend** — Priority: P0 (blocking) · P1 (high) · P2 (medium) · P3 (low/polish).
Status: `todo` · `wip` · `done` · `dropped`. Source: `user` · `audit` · `research` · `refl-research` · `refl-features` · `refl-ux`.

---

## Post-30 verification audit (2026-06-05) — "ich finde viele Sachen nicht in der App"

A 10-theme adversarial visibility audit (one agent per theme, traced code→reachable surface) confirmed **every claimed feature is present and built** — nothing is dead/unwritten. The "can't find it" is real but caused by **discoverability**, not missing code:

- **Root cause:** the entire Archiv window (segmented facets, Diktier-Statistik, Kontext/MEM-1, Verbesserungen/MEM-2, MEM-2b Lern-Vorschläge, Re-Run) was only reachable when `archiveEnabled` (default OFF) was ON **and** ≥1 entry existed — so the off-state header I built was **dead code** and the whole surface was invisible out-of-the-box (which is the privacy-first default the user asked for).

**Fixes applied (verified, 232 tests green):**

- [x] **Archiv-Fenster immer öffenbar** — added an always-visible "Archiv-Fenster öffnen …" button in the Archiv tab (works with archive OFF/empty), so the off-state header + all facets become discoverable and tell the user what to enable; removed the duplicate gated "Alle anzeigen". (ArchiveSettingsView)
- [x] **MEM-2 popover no longer advertised-but-blank** — when detection is ON but nothing mined yet, a line states results appear in the Archiv-Fenster unter Verbesserungen. (ArchiveSettingsView.improvementSection)
- [x] **Settings default tab → Prompts** — was System (tab 3) for unconfigured/new users, hiding the other tabs; the setup nudge shows on every tab anyway. (SettingsContentView.defaultTabSelection)

**Known limitations (honest):**

- **Truncation banner (Iter 22)** only renders on the manual-popover path (`WorkflowPageView`); a 180s cap is realistically only hit on eyes-off hotkey-background runs which have no persistent post-run UI surface — so the banner is effectively unreachable there. Revisit with a pill/earcon cue if it matters.
- **No Cmd+, / standard Settings window** — settings live only inside the popover (gear icon); the SwiftUI `Settings{}` scene is intentionally empty.

---

## Iteration log

- **Iter 31 — Dynamic modes, semantic email memory, variant selection (done):** autonomous sprint track completed. User-created modes now persist as ordered dynamic `ModeConfig` records with duplicate/delete/reorder/reset actions, per-mode editable hotkeys, and archive metadata preserving the concrete mode id/name. Semantic E-Mail memory is opt-in, local-vector backed via Ollama `/api/embed`, retained for 30 days, skipped for secure fields, and injected into E-Mail prompts only through explicit per-mode enrichment controls with anti-invention rules. Rewrite modes can optionally pause in the floating pill and show two generated versions before inserting/copying. +42 tests in this track, 274 tests total at completion.
- **Iter 0 (baseline, this session):** audit fixes B1/B2/B3/B4/B5/B8; pill → native Liquid Glass + ESC-cancel + processing-state + red-flash; dark-mode popover (`MenuBarStyle`+`RedeSurface`); settings 4-tab restructure (Prompts·Modelle·Archiv·System); onboarding wizard (own window, 6 steps).
- **Iter 30 — MEM-2b miner hardening (done) — 30/30 milestone:** R4-FT-suggest-direction-guard — `acceptImprovementSuggestion` now refuses a fighting INVERSE pair (dictionary already maps to→from, which would oscillate text) via a pure, tested `ImprovementMiner.conflictsWithExisting`; the unsafe suggestion is dismissed instead of dead-ending. R4-DR-miner-umlaut-boundary VERIFIED as a non-issue — added 4 umlaut/ß whole-word regression tests proving ICU `\b` sets German boundaries correctly (start/middle/end + no inside-word match); kept as a guard. **R4-DR-miner-singlesource deferred** (distinct-day gating would slow "correct-twice→learn" UX; ≥2 is acceptable). +7 tests. 232 tests.
- **Iter 29 — R4-UX onboarding & earcon discoverability (done):** FinishStep gained an "Außerdem dabei" card surfacing the opt-in extras a first-run user wouldn't find (lokales Archiv & Statistik, self-learning Lern-Vorschläge, optional Akustisches Feedback) (R4-UX-onboard-recap); the System-settings earcon preview now offers Start/Fertig/Fehler buttons instead of only `.done`, so the user hears all three sounds they enabled (R4-UX-earcon-preview). UI-only, 225 tests.
- **Iter 28 — R4-FT-secure-guard Sensitive-Field Guard (done):** dictating into a password field would otherwise store the password in the archive/Memory/improvement log. Now `PasteContextAXReader` reads the focused element's subrole and flags `AXSecureTextField` (pure, unit-tested `isSecureFieldRole`); `PasteTarget.isSecureField` carries it; `handleWorkflowRun` skips archive/context/Memory and `makeImprovementSnapshot` returns nil for a secure target — the run still pastes, but leaves NO trace. +3 tests. 225 tests. (Force-offline transcription for secure fields noted as a follow-up — needs local-model fallback handling.)
- **Iter 27 — R4 correctness/privacy bundle (done):** (1) R4-DR-earcon-nospeech — a benign no-speech take no longer plays the harsh Basso error earcon; introduced `TranscriptionQualityService.noSpeechMessage` as the single source of truth (replaced 10 literals across 4 workflows) and the earcon gate skips it. (2) R4-FT-dismiss-persist — "Verwerfen" now persists via new `AppSettings.dismissedImprovementSuggestionKeys` (tolerant decode), so declined Lern-Vorschläge stay gone across relaunch. (3) R4-DR-retention-timer — `ImprovementLogStore`/`ContextLogStore` gained `pruneExpired()`, called on `didBecomeActive`, so age-retention fires in a long-lived menu-bar process. +4 tests. 222 tests.
- **Iter 26 — MEM-2b discoverability bundle (done):** the self-learning suggestions were buried in the standalone archive window's 4th segment. Now: the Verbesserungen facet label shows a "(N)" badge when suggestions wait (R4-UX-facet-badge); the popover Archiv tab shows a one-tap "N neue Lern-Vorschläge — ansehen" nudge that opens the archive window (R4-UX-suggest-surface); the MEM-2b header renamed "Vorschläge" → "Lern-Vorschläge" to disambiguate from the Memory "Vorschläge (N)" (R4-UX-vorschlaege-naming); VoiceOver label added to the "Verwerfen" button (R4-UX-verwerfen-a11y). UI-only, 218 tests.
- **Iter 25 — R3-UX-modelgroup + R3-UX-vocabref (done):** Modelle-Tab reorganized — engines (Online · Lokal) on top, then a single "Vokabular & Ersetzungen" group bundling Eigennamen (+ fuzzy toggle) and the Diktier-Wörterbuch under one heading with a disambiguating intro caption (3 mechanisms: recognize / snap near-miss / hard-replace). UI-only, 218 tests.
- **Iter 24 — R2-FT-sound optional earcons (done):** new `EarconPlayer` plays built-in macOS system sounds (Tink/Glass/Basso) for start/done/error, wired into the single `handleWorkflowPhaseChange` hook and gated on a new opt-in `AppSettings.soundFeedbackEnabled` (default OFF, tolerant decode). Toggle + "Anhören" preview in System settings. Start earcon fires only at recording start (transcribing `.running` is silent). +5 tests (mapping/system-sound resolution/codable). 218 tests.
- **Iter 23 — R3-FT-learn / MEM-2b self-learning suggestions (done):** closes the loop the log itself flagged as open. New pure `ImprovementMiner` mines recorded corrections for a recurring, clean SINGLE-word fix (≥2 occurrences, ≥3-char core, punctuation-stripped, dedup vs dictionary) and surfaces it as a confirmable "Vorschlag" in the Verbesserungen facet — one-tap "Übernehmen" adds a whole-word `DictationReplacement`, "Verwerfen" hides it for the session. 100% on-device, opt-in, conservative. `AppState.improvementSuggestions/accept/dismiss`; section caption updated ("lernt aus deinen Korrekturen"). +12 tests. 213 tests. **User headline feature.**
- **Iter 22 — R3-DR-maxdur truncation note surfaced (done):** found a clean design — added `didTruncateAtMaxDuration` to the `Workflow` protocol (each workflow forwards `recorder.didStopAtMaxDuration`, 4 one-liners) and render a SINGLE orange banner in `WorkflowPageView` when a `.done` run's recording hit the 180s cap ("Aufnahme war zu lang … nur der Anfang wurde übernommen"). No per-view churn. 201 tests.
- **Iter 21 — R3-UX-archtabs Archiv-Fenster segmentiert (done):** the one-long-scroll Archiv window is now a native `.segmented` Picker — Verlauf · Diktate · Kontext · Verbesserungen — each facet on its own, header + picker fixed, only content scrolls. Opt-in facets show an off-hint (not blank) when disabled; "Archiv löschen" only on the Verlauf facet. UI-only, 201 tests. **R3-DR-maxdur deferred again** (truncation note needs a per-run channel reaching the success/onOutput path across 4 workflows — too much churn for a rare 180s edge; revisit with a dedicated note channel).
- **Iter 20 — R3-DR-axcap + R3-DR-categ (done):** `readFocusedValue` now caps the MEM-2 field re-read at 20 000 chars (skips whole documents — bounds the main-actor copy), and `ImprovementDiff.observe` guards the O(n²) anchor recovery above the same cap (cheap verbatim check still runs first). `categorize` gained web-app refinement: a browser whose window title names Gmail/Outlook/Notion/GitHub/Slack/… is classified as that app, not generic "Browser" (desktop bundles always win). +5 tests (web-app categorization + large-input guard). 201 tests. **R3-DR-fuzzy2 verified as a FALSE POSITIVE** (the `index+2 < count` guard is correct; loosening it would crash) → dropped.
- **Iter 19 — R3-UX Archiv-Fenster polish (done):** stat tiles → 2×2 `Grid` (no clip at min width); new reusable `DestructiveClearButton` (native `.confirmationDialog` + VoiceOver) unifies the 3 inline "Wirklich löschen" buttons (Archiv·Kontext·Verbesserungen); honest off-state header + hidden clear button when archiving is off; Verbesserungen relabel "Vorher/Nachher" → "Eingefügt/Korrektur" (was ambiguous which side was rede's). UI-only, 196 tests. (R3-UX-tiles + R3-UX-delete + R3-UX-offstate + R3-UX-micro)
- **Iter 18 — R3-DR-pid + R3-DR-retention MEM privacy hardening (done):** MEM-2 re-read now re-verifies the live app's bundle id == snapshot's before reading (kills false corrections from OS PID-reuse over the 10s defer window); `ImprovementLogStore` (text-bearing) gained 30-day age retention, `ContextLogStore` (metadata) 90-day, both pruned on append + load like ArchiveStore. New `ImprovementLogStoreTests` + retention tests in PasteContextTests. 196 tests (+7). (Deliberately did NOT auto-purge on toggle-off — destructive surprise; age-expiry + explicit "Verlauf löschen" cover the gap.)
- **Iter 17 — B6 effective-model surfacing (done):** `RewriteProvider` → `RewriteOutcome` (text + used/requested model); silent gpt-4o-mini fallback now shows a quiet note in popover + archive rerun + logs it; behavior unchanged. 189 tests (+8).
- **Iter 16 — R2-FT-stats Diktier-Statistik (done):** `DictationStats.compute` (runs/words/time-saved/per-mode), "Deine Diktate" panel in Archiv, archive-only (no privacy cost). 181 tests (+11).
- **Iter 15 — DR-4 cursor-relative context (done):** `surroundingWindow` (UTF-16, ~600-char window centered on `kAXSelectedTextRangeAttribute`) replaces ≤1500-char whole-field send to OpenAI; guarded AX read + fallback. 170 tests (+10).
- **Iter 14 — FT-3 Archiv wiederverwenden (done):** per-entry Kopieren/Transkript-kopieren + "Neu umschreiben in <Modus>" (`rerunRewrite` on stored raw transcript, backend-gated, inline result), `RewriteReuse`/`ArchiveClipboard` helpers, `ArchiveEntryRow` extracted. 160 tests (+10).
- **Iter 13 — R2-FT-fuzzy Eigennamen-Korrektur (done):** conservative `FuzzyTermCorrector` (Levenshtein budget by length, ±2 length, ambiguity + min-length guards), toggle (default on), wired post-transcription in 4 workflows. 150 tests (+10, incl. non-correction guards). (agent socket dropped at report; impl was done, I added the tests.)
- **Iter 12 — R2-DR-settings-io (done):** debounced (0.4s coalesced) + off-main settings persistence with `Sendable` snapshot, flush on resignActive/terminate, now 0600 via SecureFileWriter. 140 tests (+2).
- **Iter 11 — MEM-2 Verbesserungs-Erkennung (done):** opt-in (default OFF, gated on archive); after paste a deferred cancellable AX re-read of the field, `ImprovementDiff` (verbatim / edited-in-place via prefix+suffix anchors + Jaccard similarity guard / not-found→nil), `ImprovementLogStore` (0600, cap 200), Archiv section. 138 tests (+12). **User headline feature.**
- **Iter 10 — MEM-1 Kontext-Erkennung / Office Memory (done):** AX-read app + window title + element role at paste-target-capture time (no paste latency), `PasteContextCategory.categorize`, `ContextLogStore` (0600, cap 300, metadata-only, opt-in with archive), Archiv "Wo du diktierst" aggregate + list. 126 tests (+15). **User headline feature.**
- **Iter 9 — R2-DR-mic-auth + R2-DR-paste-fail (done):** record only with mic authorization (else clear error, not silent), and honest "In die Zwischenablage kopiert — mit ⌘V einfügen" when auto-paste can't land. AudioRecorder → @MainActor + `MainActor.assumeIsolated` timers (warnings cleared). 111 tests (+4).
- **Iter 8 — FT-1 hardening (done):** spoken-punctuation default OFF (fixes data-corruption of real words like "Punkt"), mapping reference + warning in UI, `wholeWord` toggle exposed, dark-mode tokens for the new section + chips, add-row VoiceOver + duplicate feedback. 107 tests. Reflection round 2 added ~17 ideas (below).
- **Iter 7 — FT-1 Diktier-Wörterbuch & Sprachbefehle (done):** on-device `DictationPostProcessor` (literal whole-word/substring replacements + spoken punctuation "Komma"/"Punkt"/"neue Zeile"…), `DictationDictionary` in AppSettings (tolerant migration), UI section in Modelle, wired into all 5 workflows post-transcription. 106 tests green (+18).
- **Iter 6 — B7+B9+B11+B13 audit cleanups (done):** dead `FoundationModels`/`Unavailable` providers deleted; dead `DampfAblassen.selection` param dropped; `effectiveRewriteTerms` (no Whisper cap) for rewrite prompts; Social/Emoji now uses Eigennamen. 87 tests green (+7).
- **Iter 5 — UX-1 + UX-5 (done):** VoiceOver labels (pill + workflow rows, decorative hidden); popover recording keyboard (Return=stop, Esc, hint) + error-retry shortcut. 80 tests green.
- **Iter 4 — DR-3 + DR-2 (done):** clipboard restored after auto-paste (`PasteboardSnapshot`, success-path only, ~750ms cancellable); recording max-duration auto-stop (180s) + whisper-1 25 MB upload guard. 80 tests green. (impl agent's API socket dropped during reporting, code was already green.)
- **Iter 3 — UX-4 (done):** dark-mode token consistency across 7 views (ModeCardView/Archive/Onboarding/EmptyStateCard/model views) via `MenuBarTokens`. 80 tests green.
- **Iter 2 — UX-2 + UX-3 + UX-6 (done):** onboarding keyboard (Return/Esc), umlaut-stripped copy fixed, unified destructive-delete `.confirmationDialog`. 80 tests green on first run.
- **Iter 1 — SET-1 Settings cleanup (done):** `SettingsSection`/`EmptyStateCard`/`SettingsStatusBadge` primitives; `ModeCardView` progressive disclosure ("Erweitert" + "angepasst" dot via `ModeConfig.isAdvancedNonDefault`); per-tab empty-state CTAs + cross-tab nav; System-tab merged Installation/Updates/Anmelden/Hinweis. 80 tests green (fixed an over-running logic bug in `isAdvancedNonDefault`). Reflection produced 18 new items (below).

---

## Done

- [x] **B1** reply/edit context captured before popover steals focus — `audit`
- [x] **B2** `.local` rewrite gated on a selected Ollama model (no data-loss) — `audit`
- [x] **B3** editSelection empty-selection errors before recording (+ stays visible in popover) — `audit`
- [x] **B4** local WhisperKit transcription uses Eigennamen via `promptTokens` — `audit`
- [x] **B5** memory suggestions dedupe by lemma — `audit`
- [x] **B8** `effectiveCustomTerms` memory-off branch cap+reversed — `audit`
- [x] **Pill** native Liquid Glass; ESC abort + red flash; visible during transcription; gone on paste — `user`
- [x] **Dark-mode popover** opaque backstop + colorScheme tokens + per-mode accents — `user`
- [x] **Settings 4-tab restructure** Prompts·Modelle·Archiv·System + OpenAIKeySection extracted — `user`
- [x] **Onboarding wizard** own window, 6 steps, pre-filled prompts, empty-state nudges — `user`
- [x] **SET-1 Settings cleanup** (Iter 1) — SettingsSection/EmptyStateCard, ModeCardView progressive disclosure, per-tab empty states — `research`

---

## Todo (prioritized)

### Active autonomous sprint track — Dynamic modes, semantic email memory, variant selection

- [x] **SPRINT-MODES-1** [P1 XL] Dynamic user-created modes: replace the current fixed-slot UX with an ordered user-mode list while keeping the workflow runtime compatible with existing `WorkflowType` behavior. Covers and supersedes `FT-2`.
- [x] **SPRINT-HOTKEYS-2** [P1 L] Rebindable global shortcuts per mode, with migration from the existing fn-based combos and conflict validation. Covers and supersedes the user-rebindable part of `DR-1`.
- [x] **SPRINT-MEMORY-3** [P1 XL] Semantic E-Mail memory: local embedding provider, secure vector store, retrieval, and privacy-gated ingestion from text archive runs.
- [x] **SPRINT-ENRICH-4** [P1 M] Per-mode E-Mail enrichment controls that govern retrieval volume and prompt behavior without importing unconfirmed facts.
- [x] **SPRINT-VARIANTS-5** [P1 L] Optional two-version rewrite output with an expanded recording-pill selection card before paste. Extends `R3-FT-preview`.
- [x] **SPRINT-HARDEN-6** [P1 L] Full verification, code review, review-finding fixes, documentation updates, and backlog cleanup.

### P1 — high value

- [ ] **UX-2** Return advances onboarding / Esc dismisses — `.keyboardShortcut(.defaultAction/.cancelAction)` on wizard footer (mouse-only today) [S] — `refl-ux`
- [ ] **UX-1** VoiceOver labels for pill + workflow rows (`.accessibilityElement`+label/value; today `.help`-only) [M] — `refl-ux`
- [ ] **DR-2** Guard recordings — max duration cap + mic disconnect/route-change handling + 25 MB whisper-1 upload limit [M] — `refl-research`
- [x] **DR-1** Harden global hotkeys — robust flag matching (Globe/F-key settings, nav-key collisions) + user-rebindable combos [M] — `refl-research`/`refl-features`
- [ ] **FT-1** Diktier-Wörterbuch & Sprachbefehle — local literal replacements + spoken punctuation/newline, applied before paste (deterministic, on-device) [M] — `refl-features`
- [x] **FT-2** Custom Modi — user-created/renamable/reorderable modes (prompt+backend+tone+memory) instead of 5 fixed slots [M/L] — `refl-features`
- [ ] **MEM-1 Context detection ("Office Memory")** — at paste capture app bundle id + window title (`kAXTitleAttribute`) + role; store per-context; view in Archiv. (subsumes audit B12 + DR-4) — `user`/`research`
- [ ] **MEM-2 Improvement detection** — re-read focused field via AX after paste; diff inserted-vs-final; learn patterns (opt-in) [L] — `user`/`research`

### P2 — medium

- [ ] **UX-4** Dark-mode token consistency — route `ModeCardView`/`ArchiveEntryRow`/Prompts nudge/`OnboardingCard` hardcoded `Color.primary.opacity` through the colorScheme-aware tokens (same wash-out already fixed in MenuBarView) [M] — `refl-ux`
- [ ] **UX-3** Fix umlaut-stripped German copy ("Aendern"→"Ändern", "Einfuegen", "Fuer…", `Tastenk\u{00FC}rzel`) [S] — `refl-ux`
- [ ] **UX-5** Keyboard-stop + "Eingefügt" auto-advance in popover recording (parity with the pill) [S] — `refl-ux`
- [ ] **DR-3** Restore the user's previous clipboard after auto-paste (today it's clobbered + lingers) [S] — `refl-research`
- [ ] **DR-4** Cursor-relative surrounding context via `kAXSelectedTextRangeAttribute` (today sends ≤1500 chars of whole field → privacy/noise) [M] — `refl-research`
- [ ] **DR-5** Incremental Memory recompute — persist per-document extractions (today O(archive) full re-run + main-actor stalls) [M] — `refl-research`
- [ ] **FT-3** Archiv Re-Use & Re-Run — copy / re-paste / "in anderem Modus neu umschreiben" on past entries [M] — `refl-features`
- [ ] **FT-5** Übersetzungs-/Mehrsprachen-Modus — dictate DE → paste EN (target language per mode) [L] — `refl-features`
- [ ] **B6/DR-6** surface the effective OpenAI model after a silent gpt-4o-mini fallback (log + status) — `user`/`audit`/`refl-research`
- [ ] **OB-1 Onboarding polish** — apply code-review findings + visual refinement after first real run — `user`
- [ ] **POP-1 MenuBarView split** — extract the 4 `*ActiveView` recording bodies into `WorkflowActiveViews.swift` (~1010 lines) — `audit`

### P3 — low / polish / cleanup

- [ ] **UX-6** Unify destructive-delete confirmation (`.confirmationDialog` for Archive/Memory clear; +accessibilityLabel) [S] — `refl-ux`
- [ ] **FT-6** Memory import/export (JSON/text) + one-tap "Begriff hinzufügen" from selection [S] — `refl-features`
- [ ] **B7** separate `effectiveRewriteTerms` (natural order, no Whisper cap) for the rewrite prompt — `audit`
- [ ] **B9** Social/Emoji mode: include custom terms in the rewrite prompt (or a clarifying caption) — `audit`
- [ ] **B11** delete dead `FoundationModelsRewriteProvider`/`UnavailableRewriteProvider` (+ import) — `audit`
- [ ] **B13** drop the unused `selection` param from `DampfAblassenWorkflow` — `audit`

---

## Round-2 reflection ideas (2026-06-05, after Iter 7; triage into the loop)

### Correctness / robustness

- [ ] **R2-DR-mic-auth** [P1 S] Gate recording on `AVCaptureDevice.authorizationStatus` at record time — denied/revoked grant yields a silent file + generic "Keine Aufnahme erkannt." with no permission hint — `refl-research`
- [ ] **R2-DR-route** [P2 M] Handle audio-device disconnect / route change mid-recording (the unfinished half of DR-2) — AirPods/USB mic drop → dead session, silent tail, no error — `refl-research`
- [ ] **R2-DR-paste-fail** [P2 S] Surface "kopiert — mit Cmd+V einfügen" when auto-paste silently fails (no target / focus race) instead of a false `.success` — `refl-research`
- [ ] **R2-DR-settings-io** [P2 M] Debounce + off-main settings persistence — every prompt keystroke JSON-encodes the whole container + sync disk write on MainActor — `refl-research`
- [ ] **R2-DR-mem-race** [P3 M] Serialize Memory fold vs. recompute to prevent reintroduced/stale candidates + watermark desync — `refl-research`

### New features

- [ ] **R2-FT-edit** [P1 M] Push-to-Edit follow-ups — after paste, re-trigger to dictate a correction that re-runs the rewrite on the just-produced text (conversational refine) — `refl-features`
- [ ] **R2-FT-stream** [P1 S] Stream the OpenAI rewrite (progressive pill text / incremental) to cut perceived latency on the most-used path — `refl-features`
- [ ] **R2-FT-route** [P2 M] Per-app default mode + smart routing (remember/pin mode per frontmost bundle id) — `refl-features`
- [ ] **R2-FT-fuzzy** [P2 M] Local fuzzy spell-correction snapping near-miss transcriptions to confirmed Memory/Eigennamen ("Rinert"→"Rinnert") before rewrite — `refl-features`
- [x] **R2-FT-sound** (Iter 24) Optional start/done/error earcons for eyes-off background-hotkey dictation — `refl-features`
- [ ] **R2-FT-stats** [P3 S] Daily/weekly dictation stats + "Zeit gespart" panel in Archiv (from existing ArchiveEntry data) — `refl-features`

### UX

- [ ] **R2-UX-overlap** [P2 M] Disambiguate "Eigennamen" vs "Diktier-Wörterbuch" (caption/example: recognized-correctly vs literally-replaced) — `refl-ux`
- [ ] **R2-UX-dict-a11y** [P2 S] Dictionary add-row already got VoiceOver + duplicate feedback in Iter 8 — verify parity for Eigennamen add-row too — `refl-ux`
- [ ] **R2-UX-onboard-dict** [P3 S] Mention the dictation dictionary / spoken punctuation in onboarding FinishStep recap + ModesStep — `refl-ux`

---

## Round-3 reflection ideas (2026-06-05, after Iter 17; triage into the loop)

### Correctness / robustness / privacy

- [x] **R3-DR-pid** (Iter 18) MEM-2 re-read can attach to a **reused PID** → logs a false correction: `performImprovementReread` only checks the PID is alive, never re-verifies `snapshot.bundleIdentifier` against the live `NSRunningApplication`; if the target quit and the OS recycled its PID in the 10s window it reads an unrelated app's focused field. (App/AppState.swift, PasteContextAXReader.readFocusedValue) — `refl-research`
- [x] **R3-DR-retention** (Iter 18) PII stores have a count cap but **no age retention** and aren't purged when archiving/improvement is disabled: `ImprovementLogStore` (full before/after dictation text — most sensitive) and `ContextLogStore` (window titles leaking doc names/subjects/URLs) keep newest 200/300 indefinitely; toggling off never deletes the backing files. ArchiveStore already prunes at 90 days. (ImprovementLog.swift, PasteContextLog.swift, AppState toggles) — `refl-research`
- [x] **R3-DR-axcap** (Iter 20) Unbounded AX field re-read + O(n²) anchor scan on MainActor for MEM-2: `readFocusedValue` copies the entire `kAXValueAttribute` (no length cap, unlike SelectionContextService's 600-char window), then `ImprovementDiff.stablePrefix/stableSuffix` call `contains` per character. (PasteContextAXReader.swift, ImprovementDiff.swift) — `refl-research`
- [x] **R3-DR-maxdur** (Iter 22) Max-duration auto-stop note is captured but **never surfaced**: `AudioRecorder.didStopAtMaxDuration` / "Aufnahme zu lang" is set but no workflow reads it (only `errorMessage` at `start()`), so a 180s-truncated recording pastes with zero indication the tail was cut. (AudioRecorder.swift, \*Workflow.swift stop()) — `refl-research`
- [~] **R3-DR-fuzzy2** (Iter 20: DROPPED — false positive) `twoWordMatch`'s `index + 2 < tokens.count` guard is correct; `tokens[index+2]` requires it, and the final word-pair (`index+2 == count-1`) already passes. Loosening to `<=` would crash. — `refl-research`
- [x] **R3-DR-categ** (Iter 20) PasteContext categorizer mis-buckets Electron/browser-hosted targets (Gmail/Outlook web, Teams, Notion, Linear) as "browser/other" → "Wo du diktierst" under-counts email/chat/code for web-app users. (PasteContextLog.categorize) — `refl-research`

### New features

- [ ] **R3-FT-undo** [P1 M] Paste-Undo & Verlauf-Wiedereinfügen — auto-paste is irreversible (clipboard restored on success); a global "letztes Diktat rückgängig / erneut einfügen" hotkey re-stages the last pasted text (reuses ArchiveRunRecord + PasteboardSnapshot) — `refl-features`
- [x] **R3-FT-learn** (Iter 23) **MEM-2b** Self-learning correction rules — mine `ImprovementLogStore` for recurring deterministic before→after edits and propose them as confirmable DictationDictionary entries (closes the loop the code flags as open; 100% on-device, opt-in) — `refl-features`
- [ ] **R3-FT-snip** [P2 M] Diktier-Snippets / Textbausteine — a spoken trigger phrase ("Signatur einfügen") expands to a stored multi-line block in `DictationPostProcessor` before paste (whole-phrase, deterministic, offline) — `refl-features`
- [ ] **R3-FT-voice** [P2 M] App-eigene Sprachsteuerung ("Meta-Diktat") — a dedicated hotkey whose transcript is parsed locally as a command to rede ("wechsle in E-Mail-Modus", "Archiv öffnen") instead of pasted — `refl-features`
- [ ] **R3-FT-selftest** [P2 M] Lokales LLM-Modellmanagement & Self-Test — installed size + quick on-device latency/sample-rewrite self-test + surfaced auto-fallback note when local model missing/slow (extends RewriteOutcome) — `refl-features`
- [x] **R3-FT-preview** Inline-Vorschau & Bestätigen vor Einfügen (opt-in) — rewrite modes can show two pill variants and paste only after explicit selection — `refl-features`

### UX

- [x] **R3-UX-archtabs** (Iter 21) Archiv-Fenster in Segmente/Tabs aufteilen — one ScrollView stacks 5 heavy sections (Stats·Kontext·Verbesserungen·Verlauf); a segmented `Picker` or `DisclosureGroup`s restore hierarchy/scannability (ArchiveWindowView.swift) — `refl-ux`
- [x] **R3-UX-delete** (Iter 19) Vereinheitliche drei "Löschen"-Muster — the new window sections (ArchiveWindowView/PasteContextSection/ImprovementSection) still use the old inline "Wirklich löschen", while the popover already uses `.confirmationDialog` (UX-6); migrate + accessibilityLabel — `refl-ux`
- [x] **R3-UX-tiles** (Iter 19) Vier Stat-Kacheln brechen bei Minbreite — `DictationStatsSection.statTiles` is a fixed `HStack(spacing:18)` of 4 tiles, clips at the 460pt min window width; → 2×2 `Grid`/wrap (DictationStatsSection.swift) — `refl-ux`
- [x] **R3-UX-offstate** (Iter 19) Archiv-Fenster-Header lügt im Aus-Zustand — "Lokal gespeichert … Nichts verlässt deinen Mac" shows unconditionally even when archive/context/improvement are all OFF; add an off-hint + CTA to Settings tab 2 (ArchiveWindowView.swift) — `refl-ux`
- [x] **R3-UX-modelgroup** (Iter 25) Modelle-Tab gruppieren — 6 equal-weight bands (Online·Whisper·Ollama·Eigennamen·Wörterbuch·Fuzzy); fold the 3 vocabulary blocks under a shared "Vokabular & Ersetzungen" heading (ModelsSettingsView.swift) — `refl-ux`
- [x] **R3-UX-micro** (Iter 19) Verbesserungen-Microcopy — "Vorher/Nachher" is ambiguous (Vorher=inserted rede, Nachher=user edit); relabel "Eingefügt → Deine Korrektur" + optionally hide unchanged rows (ImprovementSection.swift) — `refl-ux`
- [x] **R3-UX-vocabref** (Iter 25) Cross-reference the 3 word-replacement mechanisms (Eigennamen↔Wörterbuch↔Fuzzy) with a one-line caption at the source — `refl-ux`

---

## Round-4 reflection ideas (2026-06-05, after Iter 25; triage into the loop)

### Correctness / robustness / privacy

- [x] **R4-DR-earcon-nospeech** (Iter 27) A benign no-speech take (`phase = .error("Keine Aufnahme erkannt.")` in all 4 workflows) plays the harsh `.error` (Basso) earcon — eyes-off users hear "broke" for a normal silent take. Distinguish no-speech from real errors before `playEarcon(.error)` (AppState handleWorkflowPhaseChange, EarconPlayer) — `refl-research`
- [x] **R4-DR-retention-timer** (Iter 27) PII is only age-pruned on `append()`/`load()`, never on a timer; a long-lived menu-bar process (or one where improvement detection was turned OFF, removing the `append` wiring) keeps 30-day improvement text / 90-day context titles past the cutoff until relaunch. Prune on `didBecomeActive` (already hooked) (ImprovementLog/PasteContextLog, AppState) — `refl-research`
- [x] **R4-FT-dismiss-persist** (Iter 27) Dismissed MEM-2b suggestions are in-memory only → re-nagged with the identical suggestion on every relaunch (the ≥2× observations persist 30 days). Persist a small ignore-set (AppState dismissedSuggestionKeys) — `refl-research`
- [~] **R4-DR-miner-singlesource** (Iter 30: DEFERRED — distinct-day gating would slow learning) `ImprovementMiner` counts every `changed` observation toward `minimumOccurrences` with no per-app/date diversity — two corrections of the same word in ONE chaotic field reach ≥2 and surface a rule. Require recurrences to span ≥2 distinct sessions/dates (ImprovementMiner) — `refl-research`
- [x] **R4-DR-miner-umlaut-boundary** (Iter 30: verified non-issue + regression tests) Accepted suggestions become `wholeWord:true` → `\b…\b`; ICU word boundaries around ß/umlaut/digit edges are inconsistent, so a learned `from` ending in a non-ASCII letter can mis-match at paste. Add umlaut/ß miner+accept tests, fall back to a non-`\b` guard if needed (DictationPostProcessor, ImprovementMiner) — `refl-research`
- [x] **R4-FT-suggest-direction-guard** (Iter 30) `acceptImprovementSuggestion` dedups by exact `from` only — accepting a mined `A→B` while the dictionary holds `B→A` (or `A→C`) creates a fighting pair that corrupts text by replacement order. Detect inverse/conflicting rules before appending and warn (AppState) — `refl-research`

### New features

- [x] **R4-FT-secure-guard** (Iter 28, logging-skip; force-offline = follow-up) Sensitive-Field Guard / Auto-Privacy — detect a secure/password paste target (`AXSecureTextField` role / known-sensitive app) and for that run force offline-only transcription + skip archive/context/improvement logging + skip clipboard persistence. Closes a real PII leak (password managers, banking) the archive/MEM-2 pipeline would otherwise capture — `refl-features`
- [ ] **R4-FT-automation** [P1 M] Local automation surface — AppIntents (Shortcuts/Spotlight/Raycast) + `rede://` URL scheme for "dictate in mode X" / "rewrite selection in mode X" / "open archive". The agent-native angle the brand promises but the code has zero of; no new always-on server — `refl-features`
- [ ] **R4-FT-silence** [P2 M] Silence-aware auto-stop & dead-air trim — the recorder meters `averagePower` but never acts; opt-in "stop after N s of silence" (true hands-free) + trim leading/trailing dead air before upload (smaller payload, fewer hallucinated tails) — `refl-features`
- [ ] **R4-FT-backup** [P2 M] One-file Backup & Restore (settings + vocabulary, NOT transcripts) — encode `AppSettings` (modes, prompts, Eigennamen, dictionary, fuzzy/Memory terms) to a single JSON for export/import; excludes archive/context/improvement PII. Full config portability for reinstalls/new Macs (distinct from memory-only FT-6) — `refl-features`
- [ ] **R4-FT-confidence** [P2 M] Confidence-gated re-dictate — surface Whisper low-confidence (avgLogprob / no-speech) and on a garbled/empty run show a one-tap "Nochmal aufnehmen" in the pill instead of pasting noise; reuses `TranscriptionQualityService` + the pill's error-retry affordance — `refl-features`
- [ ] **R4-FT-cheatsheet** [P3 S] Hotkey cheat-sheet overlay — transient dismissible overlay (from menu bar + once post-onboarding) showing the 5 live chords, hold-vs-toggle, ESC-cancel; the Fn-chords are invisible outside onboarding — `refl-features`

### UX

- [x] **R4-UX-suggest-surface** (Iter 26) Surface MEM-2b "Vorschläge" where users look — they only render in the separate Archiv window's 4th segment; add a count badge on the popover Archiv tab + an inline "N neue Vorschläge — übernehmen?" nudge in `ArchiveSettingsView.improvementSection` (AppState.improvementSuggestions) — `refl-ux`
- [x] **R4-UX-facet-badge** (Iter 26) Badge the "Verbesserungen" facet segment when actionable — the segmented picker shows bare labels; append a count/dot to the facet label when a suggestion waits (ArchiveWindowView facetPicker/Facet.label) — `refl-ux`
- [x] **R4-UX-onboard-recap** (Iter 29) Recap newly-shipped features in onboarding FinishStep — recap covers only Mikrofon/Bedienungshilfen/Verarbeitung/Whisper/Modi; add a line each for local Archiv, self-learning Verbesserungen, optional Akustisches Feedback (FinishStepView; mirror per R2-UX-onboard-dict) — `refl-ux`
- [x] **R4-UX-earcon-preview** (Iter 29) Earcon preview plays only `.done` — offer Start/Fertig/Fehler preview so the user hears all three sounds they enabled (SystemSettingsView feedbackSection) — `refl-ux`
- [x] **R4-UX-vorschlaege-naming** (Iter 26) Two identically-named "Vorschläge" surfaces (Archiv-Tab Memory vocabulary terms vs Verbesserungen MEM-2b correction rules) — rename one (e.g. "Lern-Vorschläge" / "Wörterbuch-Vorschläge") so they don't conflate (ArchiveSettingsView vs ImprovementSection) — `refl-ux`
- [x] **R4-UX-verwerfen-a11y** (Iter 26) Missing VoiceOver label on the suggestion "Verwerfen" button (Übernehmen has one, Verwerfen reads as a bare verb) (ImprovementSection ImprovementSuggestionRow) — `refl-ux`

---

## User requests (2026-06-10)

- [ ] **FT-7 Live-Transkript (Realtime-Diktat-Vorschau)** [P1 L] Optional setting for the plain dictation modes (`transcription`/`localTranscription`, NOT the rewrite modes): show a live rolling transcript while recording instead of record-then-transcribe only. Recommended path: WhisperKit streaming transcription on-device — native for the local mode, and as a **local-only preview** for the online mode (final text still whisper-1; preview audio/text never leaves the Mac; requires an installed local model → gate the toggle on local-transcription readiness). Explicitly out of scope for v1: OpenAI Realtime API streaming (new WebSocket transport + per-minute cost). UI: recording pill grows an expandable live-text area (labeled "Vorschau"; partials self-correct while speaking — expected streaming behavior). Setting: `AppSettings` toggle, default OFF, `decodeIfPresent` default + missing-key tests. Distinct from R2-FT-stream (that one streams the rewrite RESPONSE, not live transcription). — `user`
