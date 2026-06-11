# rede — Design System

Visuelle Sprache der Menüleisten-App **rede** (Spin-off des Blitztext-Designsystems; interne
Komponentennamen behalten das Blitz-Präfix für günstige Upstream-Merges). Neue UI muss sich hier
einfügen.

## Marke — „Voice-First / Electric"

- Wortmarke: **rede**, immer klein geschrieben — auch am Satzanfang (wie „iPhone") — mit einem
  Akzent-Punkt: `rede.` Der Punkt ist Statement + Voice-Cue. Gerendert über die `Wordmark`-View
  in SF Rounded Bold; der Punkt nutzt `RedeBrand.dotColor` (lime auf dunklen Flächen, violet auf
  hellen — lime würde auf Weiß ausbleichen).
- Brand-Farben (`RedeBrand`, Single Source in `MenuBarStyle.swift`):
  - **Electric Violet `#6E56F8`** — primärer Markenakzent, in beiden Modi lesbar, zeitlos-digital.
  - **Acid Lime `#CCFF1A`** — High-Energy-„live"-Pop. NUR auf dunklen/Ink-Flächen lesbar
    (App-Icon, Aufnahme-Zustand, dunkle Kontexte) — niemals als Text auf hellem Fill.
  - **Ink `#0E0B1A`** — fast-schwarzer Markengrund (Icon, dunkle Akzentflächen).
- Typo-Charakter: **SF Rounded** für die gesamte Popover-/Window-UI (`.fontDesign(.rounded)` am
  Root) — jung, freundlich, ohne Font-Bundling. Monospace-Runs (Hotkeys, Pfade) setzen
  `.monospaced` explizit und bleiben unberührt. Gilt für ALLE Fenster-Roots: Popover
  (`MenuBarView`), Onboarding (`OnboardingWizardView`), Archiv-Fenster (`ArchiveWindowView`),
  Lokale Modelle (`LocalModelsView`).
- Icon-Motiv: weiße Sprechblase (Tail unten links) mit einer **Acid-Lime Voice-Waveform** auf
  Electric-Violet-Rundquadrat. Deterministisch aus `scripts/generate-icons.swift`.

## Tonalität

- Ruhig, dicht, funktional. Deutschsprachige UI-Texte (du-Form, knapp).
- Menüleisten-Popover, feste Breite **410pt** (vorher 340) — mehr Luft für die 5 Settings-Tabs + dichten Inhalt.
- Settings-Tabs (segmented): **Prompts · Modelle · Vokabular · Archiv · System**. Alles Wort- und Memory-bezogene lebt im **Vokabular**-Tab: ein zentraler Memory-Master, E-Mail Memory, Korrekturlernen und **Begriffe** (inkl. der **Ersetzungen** als Unterblock — sie sind für den Nutzer dieselbe Idee). **Archiv** = nur Verlauf/Statistik/Kontext.
- Vokabular ist bewusst **klein gehalten**: die Begriffsliste (manuell + automatisch gelernt) ist auf **30** gedeckelt (`MemoryStore.injectionCap`/`maxConfirmed`), damit nicht hunderte Begriffe lernen und der Whisper-Prompt knapp bleibt. Gesprochene Satzzeichen gibt es nicht (entfernt).
- Schwebende **Pille**: Kapsel-Glass (`PillGlassModifier`) für Aufnahme/Status; für erweiterte **Copy- und Varianten-Karten** ein eigener `CardGlassModifier` (abgerundetes Rechteck, 14pt-Radius, tieferer Schatten) statt Kapsel — sonst „eckiger Inhalt im Pillen-Loch".

## Iconsprache (rede icon language)

Ein SF Symbol pro Konzept, app-weit identisch — Icons erklären, die Überschrift benennt. Alle
Sektions-Header (`SectionLabel(text:icon:)` / `SettingsSection(_:icon:)`) tragen ihr Konzept-Icon
(10pt, `.semibold`, `.secondary` — gleiche Farbe wie das Label, nie lauter als der Text).

| Konzept | Symbol | | Konzept | Symbol |
|---|---|---|---|---|
| diktat/mikrofon | `mic` / `mic.fill` | | memory | `brain` |
| Whisper/transkription | `waveform` | | identität | `person.crop.circle` |
| sprachmodell (LLM) | `text.bubble` | | begriffe | `character.book.closed` |
| verarbeitung | `cpu` | | ersetzungen | `arrow.left.arrow.right` |
| OpenAI-Key | `key.fill` | | archiv | `archivebox` |
| hotkeys | `keyboard` | | statistik | `chart.bar` |
| modi | `rectangle.stack` | | kontext | `scope` |
| bedienungshilfen | `accessibility` | | lernen/verbessern | `wand.and.stars` |
| installation | `arrow.down.app` | | updates | `arrow.triangle.2.circlepath` |
| töne | `speaker.wave.2` | | embedding | `point.3.connected.trianglepath.dotted` |
| autostart | `power` | | einrichtung | `sparkles` |
| über/lizenzen | `info.circle` | | entfernen (destruktiv) | `trash` |

Aktions-Verben auf Buttons (als `Label`): laden = `arrow.down.circle.fill`, prüfen/neu laden =
`arrow.clockwise`, löschen = `trash` (alle destruktiven Aktionen inkl. `DestructiveClearButton`),
fenster öffnen = `macwindow`, system-panel öffnen = `arrow.up.forward.app`, einfügen aus
zwischenablage = `doc.on.clipboard`, analysieren = `sparkle.magnifyingglass`, weiter (wizard) =
trailing `chevron.right`. Kurze Banner-CTAs („öffnen", „prüfen") und Abbrechen bleiben textonly.

## Farben

- Akzent pro Modus: `transcription`=blue, `localTranscription`=green, `textImprover`=purple,
  `dampfAblassen`=orange, `emojiText`=cyan.
- Status: grün = bereit/erfolg, orange = Achtung/fehlende Rechte, rot = Fehler.
- Flächen: `Color.primary.opacity(0.03–0.06)` für Karten; `controlBackgroundColor` für Felder.

## Typografie (SF, system)

- Sektionslabel: 11pt, `.medium`, `.secondary`, UPPERCASE (`SectionLabel`).
- Titel/Row-Titel: 11.5–14pt, `.semibold`.
- Fließtext/Hinweise: 10.5–11.5pt, `.secondary`.
- Monospace nur für Tastenkürzel/Pfade/Key-Maskierung.

## Abstände & Form

- Ecken-Radien: Felder 6pt, Karten/Banner 8–10pt, Capsules für Chips.
- Card-Padding 10pt, Screen-Padding 16pt.
- Rahmen: `strokeBorder(Color.primary.opacity(0.05–0.12), lineWidth: 0.5)`.

## Komponenten

- Stock SwiftUI zuerst: `Form`-artige vertikale Gruppen, native `Picker`,
  `Toggle`, `TextField`, `TextEditor`, `.bordered` / `.borderedProminent` Buttons.
- **Eine Sektionskarte für alle Settings-Tabs**: `settingsGroupBackground()` (12pt-Radius,
  `primary.opacity(0.03)`-Fill, 0.06-Stroke, 12pt-Padding) ist die einzige Sektions-Fläche in den
  fünf Tabs. `SettingsSection` rendert Label, optionale Status-Pille, optionale Header-Aktion und
  Caption IN dieser Karte (kein `GroupBox` mehr — der erzeugte Box-in-Box-Look und floatende
  Header). Modus-Karten (`ModeCardView`) nutzen dieselbe Karte mit dem Header in der Karte;
  der Modus-Hotkey erscheint dort als Mini-Keycaps (`liquidGlassKeycap`, 9pt monospaced),
  ausgeblendet solange keine Kombination gesetzt ist.
- `EmptyStateCard`: getönte Banner-Karte (`.tintBanner`, flach) mit Icon+Titel-Zeile, Caption
  und optionaler CTA — Guidance, keine weitere Sektions-Box und kein Glass in der Karte.
- `SubtleButtonStyle` nur noch für sehr kleine Inline-/Chip-Aktionen, nicht für echte Buttons.
- Neue sichtbare Action-Buttons: `PopoverActionButtonStyle(.primary/.secondary/.warning/.danger/.quiet)`.
  Echte Aktionen dürfen nicht wie nackter Text aussehen; auch kleine Aktionen bekommen Fill/Stroke
  oder werden als Icon-Button (`PopoverIconButtonStyle`) gerendert.
- **Button-Typo kommt ausschließlich vom Style** (11pt `.semibold`, auch in den Glass-Styles):
  KEINE `.font(...)`-Modifier an Buttons oder in Button-Labels — äußere sind wirkungslos, innere
  erzeugen abweichende Button-Größen. Custom-Chrome, das wie ein Button aussehen muss (z. B.
  Menu-Labels), nutzt dieselben 11pt `.semibold`.
- Status statt Erklärung: `BlitzStatusPill` für bereit/warnung/download/online/lokal/muted.
- Längere Hinweise nur hinter `InfoDisclosure`; Settings zeigen Zustand + nächste Aktion, keine
  dauerhafte Dokumentation.
- `SectionLabel(text:)` für Abschnittsüberschriften.
- Chips: Capsule + 0.5pt Border, kleines `xmark` zum Entfernen (`FlowLayout`).
- Picker: `.segmented` für 2–3 KURZE Optionen, sonst Menu-Picker (auch wenn die Labels lang sind), `.controlSize(.small)`.
- Toggles: `.switch`, `.controlSize(.small)`.

## Neue Muster (dieser Ausbau)

- **Dynamische Modus-Karte** in den Einstellungen: Name-TextField + „Aktiv"-Toggle +
  Hotkey-Recorder + Modell-Picker + „Verarbeitung: Online/Lokal"-Picker +
  System-Prompt-`TextEditor` + Reset/Löschen/Reihenfolge. Eigene Modi dürfen gelöscht und
  verschoben werden; feste Standard-Slots nur zurückgesetzt.
- **Hotkey-Recorder**: Ein einzelnes Aufnahmefeld startet eine explizite Aufnahme. Alle erkannten
  Tasten werden live als Keycaps angezeigt; gespeichert wird erst über `Übernehmen`, `Esc` bricht
  ab. Während der Aufnahme sind Blitztext-Hotkeys global pausiert, damit vorhandene Belegungen
  nicht auslösen. Unterstützt Modifier-only, einzelne Taste, Modifier + Taste und mehrere Tasten.
  Konflikte erscheinen direkt unter dem betroffenen Modus und blockieren `Übernehmen`.
  Tastenkürzel bleiben monospaced, aber nicht dominant.
- **Memory**: Im Vokabular-Tab ein zentraler Master-Schalter mit Status-Pill. Dieser aktiviert
  Archiv, Vokabular-Memory und E-Mail Memory inklusive Modellvorbereitung; Korrekturlernen bleibt
  ein kleiner Unter-Schalter. Vokabular-Memory lernt konservativ automatisch: Namen/Fremdwörter nach
  zwei getrennten Vorkommen, Fachbegriffe nach drei; normale Alltagswörter werden über 200+
  deutsche, 200+ englische und app-spezifische Noise-Wörter gefiltert. In Modi gibt es nur einen
  per-mode Toggle `Memory nutzen`; E-Mail zeigt zusätzlich den 3er-Segmented Picker
  (`Wenig/Mittel/Viel`). Keine langen Memory-Erklärungen in der Moduskarte.
- **Eigene Identität**: Onboarding fragt einmal nach dem eigenen Namen — direkt auf dem
  Welcome-Schritt (die einzige Entscheidung dort). Derselbe Wert steht im Vokabular-Tab und wird
  lokal als feste Schreibperspektive (`Ich schreibe als ...`) sowie als Spracherkennungs-Hinweis
  verwendet. Das ist kein E-Mail-Memory, sondern Basis-Kontext für alle Rewrite-Modi;
  E-Mail-Kontext kann damit Absender/Empfänger sauberer aus `Von`/`An` ableiten.
- **Onboarding-Journey (9 Schritte)**: start (Intro + Name) → speicherort → rechte →
  verarbeitung → modelle → modi → hotkeys (Halten/Umschalten-Entscheidung + read-only
  Keycap-Liste der Modus-Hotkeys) → extras (Opt-ins: Autostart, Töne, Archiv & Memory) →
  fertig (Recap inkl. Hotkey-Modus und Extras). Bearbeitung einzelner Hotkey-Kombinationen bleibt
  in der Modus-Karte (Prompts-Tab) — das Onboarding zeigt sie nur.
- **Onboarding-Wizard-Chrome** (echtes Setup-Assistant-Muster, keine Settings-Sidebar):
  zentrierter Hero pro Schritt — 64pt-Icon-Tile (18pt-Radius, `tintFill`/`tintStroke` im
  Schritt-Akzent) + Headline (21pt bold rounded, rede-Voice mit Punkt: „lass uns reden.") +
  einzeilige Subheadline (12pt secondary, zentriert). Schritt-Views rendern NUR ihre Controls in
  einer Spalte (maxWidth 440). Footer: zurück (links) · Fortschritts-Dots (zentriert; aktiver
  Dot = 18pt-Kapsel in `RedeBrand.violet`, besucht 0.28, offen 0.12) · weiter-CTA
  (`GlassProminentButtonStyle` mit trailing `chevron.right`). „später" als quiet-Button oben
  rechts. Headline/Subheadline leben als Step-Metadaten im `OnboardingViewModel`.
  Fenster ~660×700, min 620×640, Hochformat.
- **Varianten-Karte in der Pille**: zwei gleich gewichtete Textkarten, je `Einfügen` und
  `Kopieren`. Keine automatische Paste, solange die Karte sichtbar ist.
- **Verfügbarkeits-Badges**: vorhandene Icons `checkmark.circle.fill` (grün) /
  `arrow.down.circle.fill` (blau) / `exclamationmark.triangle.fill` (orange) wiederverwenden.
- **Einheitliche Modellverwaltung**: Das „Lokale Modelle"-Fenster (`LocalModelsView`) verwaltet alle
  drei lokalen Modelltypen an einem Ort — Transkription (Whisper, `WhisperModelsSection`),
  Umschreiben (Ollama-LLM) und Embedding. Jede Modellzeile folgt demselben Muster: grün/blau-Badge +
  Name + Größe links, rechts Aktion(en) — `Nutzen`/`Aktiv`-Pille, `arrow.clockwise`-Icon-Button für
  „Neu laden" und `DeleteModelButton` (Papierkorb mit Bestätigung). `DeleteModelButton` ist
  Closure-basiert und für alle Modelltypen identisch. Reihen liegen auf `.tokenCard(cornerRadius: 8)`
  (die app-weite Listen-Reihen-Fläche), je Engine eine `SectionLabel`-Gruppe. Embedding-Modelle zeigen nie „Nutzen" (das setzt nur das
  Sprachmodell), sondern eine `Embedding`-Pille. Jeder Modelltyp muss löschbar und neu ladbar sein.
- **Offline-/Lokal-Hinweis**: orange Info-Banner-Muster wie `accessibilityHintBanner`.

## Regeln

- Keine neuen Akzentfarben ohne Grund; bestehende Modus-Akzente nutzen.
- Sensible Hinweise (Datenfluss zu OpenAI, Aufnahmen) immer als 10.5pt `.secondary`-Caption.
- Icons aus SF Symbols, gewichtet `.medium`/`.semibold`.
- User-Journey pro Bereich: oben Status, dann primäre Aktion, dann optionale Details.
- Onboarding ist Setup, nicht Handbuch: pro Schritt maximal eine Hauptentscheidung oder ein
  Berechtigungs-/Installationsstatus.
- Liquid Glass nicht stapeln: Popover/Floating-Pill bekommen Glass; innere Settings-Flächen nutzen
  native SwiftUI-Controls, damit macOS 26 den Systemlook selbst rendern kann.

## Liquid Glass v2 — Design Direction

### Geltungsbereich — Flächen-Hierarchie (HARD CONSTRAINT)

**Glass = schwebendes Chrome. Tokens = Inhaltsflächen.** Konkret:

- Liquid Glass erhalten nur Views, deren DIREKTER Parent ein schwebender Backdrop ist: das
  Popover (`BlitztextSurface`), die Recording-Pille, die Onboarding-Fenster-Wurzel — plus die
  direkt darauf liegenden Banner/Karten (`accessibilityHintBanner`, `setupNudgeBanner`,
  `truncationBanner`, `OnboardingCard`) und Keycaps (`liquidGlassKeycap`).
- ALLES, was in einer Sektionskarte (`settingsGroupBackground`/`SettingsSection`) oder in
  Fenster-Listen steckt — Reihen, Empty-States, Warn-Banner, Vorschlags-Banner, Stat-Tiles,
  Modell-Reihen — liegt auf den FLACHEN Token-Primitives aus `DesignTokens.swift`:
  `.tokenCard(cornerRadius:)` (neutral, `MenuBarTokens.cardFill`) und
  `.tintBanner(_:cornerRadius:)` (akzentuiert, `MenuBarTokens.tintFill/tintStroke`) — auf ALLEN
  macOS-Versionen identisch.

### Regel: Glass nicht stapeln

Ein Glass-Layer pro Surface-Ebene. Im Popover: `BlitztextSurface` (Fenster-Backdrop) = Layer 1, direkt aufliegende Banner = Layer 2 — Schluss. Innerhalb von Sektionskarten existiert KEIN Glass (siehe Flächen-Hierarchie oben); Chips, Toggles, Picker erben den Systemlook.

### Lesbarkeit auf Glas (HARD CONSTRAINT)

Akzent-getönte Glass-Flächen (`liquidGlassCard(accent:)`, `liquidGlassTintedCard`,
`liquidGlassInfoBanner`) tinten auf macOS 26 mit `accent.opacity(LiquidGlass.tintedGlassOpacity)`
(= 0.35), NIE mit voller Akzentfarbe — auf gesättigtem Farbglas wird `.secondary`-Text unlesbar.
Texteingabeflächen (`TextEditor`, custom Felder) liegen auf `Color(nsColor: .textBackgroundColor)`
mit `separatorColor`-Hairline, nie auf `primary.opacity(0.03)`-Wäschen (in Dark Mode unsichtbar).

### Gating-Strategie (HARD CONSTRAINT)

Alle `@available(macOS 26.0, *)` Guards **ausschließlich** in `BlitztextMac/Features/Shared/LiquidGlass.swift`. Views rufen nur benannte Wrapper-Modifier auf:

```
.liquidGlassCard(accent:cornerRadius:)
.liquidGlassCapsule(accent:)
.liquidGlassTintedCard(accent:cornerRadius:)
.liquidGlassInfoBanner(accent:cornerRadius:)
.liquidGlassKeycap()
GlassEffectContainerView(spacing:axis:content:)
.glassRowBackground(id:namespace:isHovered:accentColor:)
GlassActionButtonStyle
GlassProminentButtonStyle
```

Views dürfen **nie** `.glassEffect`, `GlassEffectContainer` oder `if #available` direkt verwenden.

### Fallback-Strategie (macOS 14–25)

Jeder Wrapper hat einen expliziten Fallback:

- `liquidGlassCard`: `MenuBarTokens.cardFill` + 0.5pt `strokeBorder(cardStroke)`
- `liquidGlassCapsule`: `.regularMaterial` + `Capsule` clip + Shadow
- `liquidGlassTintedCard`: `MenuBarTokens.tintFill(accent)` + `tintStroke`
- `liquidGlassInfoBanner`: identisch zu `liquidGlassTintedCard`
- `liquidGlassKeycap`: `MenuBarTokens.keycapFill/keycapStroke` RoundedRectangle fill + strokeBorder
- `GlassEffectContainerView`: plain `VStack` / `HStack`
- `glassRowBackground`: `RoundedRectangle.fill(tintFill)` bei hover, `.clear` sonst
- `GlassActionButtonStyle`: `PopoverActionButtonStyle(.primary)`
- `GlassProminentButtonStyle`: `PopoverActionButtonStyle(.primary)`

### Glass-Kit API Surface

Definiert in `BlitztextMac/Features/Shared/LiquidGlass.swift`. Alle existierenden Definitionen (`PillGlassModifier`, `CardGlassModifier`, `BlitztextSurface`, `liquidGlassCard`, `liquidGlassCapsule`) bleiben erhalten und werden ergänzt um:

1. **`liquidGlassTintedCard(accent:cornerRadius:)`** — für farbige Banner/Karten (orange Warnings, blaue Recommendations)
2. **`liquidGlassInfoBanner(accent:cornerRadius:)`** — semantisch identisch zu `liquidGlassTintedCard`, expliziter Name für Banner-Kontexte
3. **`liquidGlassKeycap()`** — für `HotkeyBadge`-Keycaps (clear glass auf macOS 26)
4. **`GlassEffectContainerView`** — SwiftUI-Wrapper um `GlassEffectContainer(spacing:)` auf macOS 26, plain VStack/HStack auf älter
5. **`.glassRowBackground(id:namespace:isHovered:accentColor:)`** — für `WorkflowRowView` hover mit `.glassEffectID` morphing
6. **`GlassActionButtonStyle`** — `.buttonStyle(.glass)` auf macOS 26, `PopoverActionButtonStyle(.primary)` auf älter
7. **`GlassProminentButtonStyle`** — `.buttonStyle(.glassProminent)` auf macOS 26, `PopoverActionButtonStyle(.primary)` auf älter

### Neue Tokens

- `MenuBarTokens.keycapFill(colorScheme:)` — analog zu `cardFill`, für HotkeyBadge
- `MenuBarTokens.keycapStroke(colorScheme:)` — analog zu `cardStroke`, für HotkeyBadge
- `MenuBarTokens.keycapText(colorScheme:)` — replaces the 8 inline color literals in `HotkeyBadge`
- `LiquidGlass.pillExpandedWidth: CGFloat = 340` — gemeinsame Breite für `copyOnlyContent` und `variantChoiceContent`
- `LiquidGlass.cardCornerRadius: CGFloat = 10` — Standard für Settings-Karten
- `LiquidGlass.pillCardRadius: CGFloat = 14` — Standard für Pill-Expanded-Karten (CardGlassModifier)

### Komponenten-Muster

**Engine Panel / Cards im Popover**: `.liquidGlassCard()` ersetzt manuelles `RoundedRectangle.fill` + `.overlay(strokeBorder)`.

**Farbige Banner**: direkt auf dem Popover-Backdrop (orange Warnings, blaue Setup-Nudge) →
`.liquidGlassInfoBanner(accent:)`. Innerhalb von Sektionskarten/Listen → `.tintBanner(_:)`
(flach, Tokens) — siehe Flächen-Hierarchie.

**Workflow-Reihen**: `GlassEffectContainerView` umschließt die `ForEach`-Liste; `.glassRowBackground(...)` gibt jedem Row den hover-morphing effect.

**Hotkey-Keycaps**: `.liquidGlassKeycap()` auf jedem Keycap-Token.

**Pill-Erweiterungskarten**: `.modifier(CardGlassModifier())` bleibt, ergänzt um `.shadow(color: .black.opacity(0.15), radius: 20, y: 5)` auch auf macOS 26.

**Onboarding-Karten**: `OnboardingCard` nutzt `.liquidGlassCard(accent:)` statt manueller Hintergrund/Border-Konstruktion.

**Action Buttons (primär)**: `GlassActionButtonStyle` / `GlassProminentButtonStyle` für die wichtigste CTA in schwebenden Surfaces (Pille, Onboarding-Footer).

### Chip-Backgrounds

Chips (RecognizeChip) **innerhalb GroupBox** nutzen `ChipBackgroundModifier` aus `LiquidGlass.swift`: auf macOS 26 `.thinMaterial` (kein `.glassEffect` — no-stacking-Regel), auf macOS 14–25 `MenuBarTokens.tintFill/tintStroke`.

### Informationsarchitektur-Regeln (app-weit)

- **Status → primäre Aktion → optionale Details** gilt auf jeder Seite und in jeder Karte.
- `enginePanel` im Popover: Footer-komprimiert als `BlitzStatusPill`, on-tap expandierbar.
- Settings-Tabs: Status-Pills leben in den Sektions-Headern, nicht als duplizierende Top-Level-Reihe.
- Lange Erklärungen: ausschließlich hinter `InfoDisclosure`. Kein dauerhafter Erklärungstext.
- `setupNudgeBanner`: nur auf Tab 0 (Prompts), nicht tabs-übergreifend.
- `workflowHeader`: Modus-Name auf `.semibold` 13pt, Akzentfarbe auf Icon.
- **Modelle-Tab = flache Kartenliste**: verarbeitung → OpenAI API Key → lokale transkription
  (Whisper) → lokales sprachmodell. Status-Pills sitzen in den Karten-Headern; die zum gewählten
  Verarbeitungspfad nicht passende Karte wird auf 0.45 gedimmt, bleibt aber bedienbar. Das lokale
  Sprachmodell wird nie gedimmt (per-Modus-Rewrite funktioniert in beiden Pfaden). Keine
  Band-Zwischenüberschriften mehr.
- **Installierte Modelle sind direkt wählbar**: Bereits geladene Modelle (Whisper UND GGUF)
  erscheinen im Modelle-Tab als `ModelSelectRow`-Reihen (grüner Check + „aktiv"-Pille bzw.
  „nutzen"-Button) — kein Fenster-Umweg fürs Aktivieren. Downloads liegen hinter einem leisen
  „weiteres modell laden …"-Button (eigener Download-Picker, getrennt von der aktiven Auswahl);
  Laden eines Modells aktiviert es. **Adoption-Regel**: zeigt die persistierte Auswahl auf nichts
  Installiertes, während andere Modelle auf der Platte liegen, übernimmt
  `AppState.adoptInstalledLocalModelsIfNeeded()` das erste installierte (für beide Engines; bei
  Whisper nicht während eines laufenden Downloads).
- **Archiv-Tab**: eine `SettingsSection`-Karte mit Status-Pille (aus · aktiv · N einträge) im
  Header.
- Systemeinstellungen-Reihenfolge: Bedienungshilfen → Installation & Start → Tastenkürzel →
  Diktat → Akustisches Feedback → Einrichtung → Updates → Über & Lizenzen → Sauber Entfernen.
  Die Tastenkürzel-Sektion trägt EINE `SectionLabel`-Überschrift, dann die
  Halten/Umschalten-Entscheidung mit Erklärzeile, dann die read-only Modus-Tabelle plus
  Querverweis „ändern … im tab prompts" — kein doppelter Recorder im System-Tab.

### In-App-Copy bleibt Deutsch — durchgängig kleingeschrieben

Alle Labels, Buttons, Captions, Tooltips in Deutsch (du-Form, knapp). Code, Kommentare, Commits in
Englisch.

**rede-Voice (Marken-Tonalität):**

- **Konsequente Kleinschreibung** der gesamten nutzersichtbaren UI-Copy — auch Substantive und
  Satzanfänge (Teil der Wortmarke-Logik „rede."). Ausnahmen: feststehende Eigennamen/Akronyme
  (OpenAI, GGUF, Whisper, macOS, ⌘V, Mac), die ihre Schreibweise behalten — auch als Teil von
  Komposita (Whisper-Modell, E-Mail-Memory, OpenAI-Key, Hugging-Face-Katalog). Modus-Namen
  (Diktat, E-Mail, Prompt, Social) gelten als Eigennamen der Modi und bleiben großgeschrieben.
  Fehler-/Diagnosetexte (`LocalizedError`) dürfen normale Satz-Großschreibung behalten —
  Klarheit schlägt Branding.
- Lockerer, junger Ton mit dosiertem Gen-Z-Einschlag — aber funktionale Labels bleiben eindeutig.
  Gut: „läuft", „sitzt.", „lass uns reden", „läuft … ich hör zu". Status-/Erfolgs-/Onboarding-Copy
  darf Charakter zeigen; Fehlertexte und sicherheits-/datenschutzrelevante Hinweise bleiben klar
  und nüchtern.

### Recording-Pille (Brand-Präsenz)

Der Live-Punkt der schwebenden Pille trägt das **rede-Violett** (`RedeBrand.violet`, via `tint`),
nicht den per-Modus-Akzent — so liest sich die Pille auf einen Blick als „rede". Die Waveform
behält den Modus-Akzent zur Modus-Kodierung. Rot nur im Abbruch-Zustand.

## App- und Menüleisten-Icons

- App-Icon: **Electric-Violet (`#6E56F8`) Rundquadrat** mit dem rede-Mark — weiße Sprechblase
  (Tail unten links) mit einer **Acid-Lime (`#CCFF1A`) Voice-Waveform**. Keine Zusatzsymbole,
  keine lauten Illustrationen.
- Quelle: `scripts/generate-icons.swift` rendert Iconset, `AppIcon.icns` und Menüleisten-PNGs
  deterministisch (CoreGraphics) — Icon-Änderungen passieren im Skript, nicht in Bild-Editoren.
  Danach: `iconutil -c icns <out>/rede.iconset -o AppIcon.icns` + PNGs ins Resources-/Asset-Set.
- macOS 26 Icon: `AppIcon.icon` ist die primäre Liquid-Glass-Quelle. Der Violett-Verlauf liegt
  als Icon-Composer-Fill an, das rede-Mark als SVG-Layer (`rede-mark.svg`); `AppIcon.icns` bleibt
  Fallback für ältere macOS-Darstellungen.
- Menüleisten-Icon: Idle ist das monochrome Template des rede-Marks (Sprechblase, Welle
  transparent gestanzt). Während Aufnahme/Verarbeitung keine mode-spezifischen Badge-Symbole;
  nur das normale Zeichen plus kleiner pulsierender Statuspunkt.
