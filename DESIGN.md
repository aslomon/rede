# rede — Design System

Visuelle Sprache der Menüleisten-App **rede** (Spin-off des Blitztext-Designsystems; interne
Komponentennamen behalten das Blitz-Präfix für günstige Upstream-Merges). Neue UI muss sich hier
einfügen.

## Marke

- Wortmarke: **rede**, immer klein geschrieben — auch am Satzanfang (wie „iPhone").
- Brand-Akzent: **Coral `#FF5C4D`** (sRGB 1.00/0.36/0.30). Nur für Branding-Flächen (App-Icon,
  künftige Landing-/Store-Assets) — NICHT als zusätzlicher UI-Akzent; die Modus-Akzente unten
  bleiben unverändert.
- Icon-Motiv: Sprechblase mit drei Sprechbalken (mittlerer Balken Coral) auf schwarzem Grund —
  gleiche reduzierte Stilsprache wie das Blitztext-Original, anderes Mark.

## Tonalität

- Ruhig, dicht, funktional. Deutschsprachige UI-Texte (du-Form, knapp).
- Menüleisten-Popover, feste Breite **410pt** (vorher 340) — mehr Luft für die 5 Settings-Tabs + dichten Inhalt.
- Settings-Tabs (segmented): **Prompts · Modelle · Vokabular · Archiv · System**. Alles Wort- und Memory-bezogene lebt im **Vokabular**-Tab: ein zentraler Memory-Master, E-Mail Memory, Korrekturlernen und **Begriffe** (inkl. der **Ersetzungen** als Unterblock — sie sind für den Nutzer dieselbe Idee). **Archiv** = nur Verlauf/Statistik/Kontext.
- Vokabular ist bewusst **klein gehalten**: die Begriffsliste (manuell + automatisch gelernt) ist auf **30** gedeckelt (`MemoryStore.injectionCap`/`maxConfirmed`), damit nicht hunderte Begriffe lernen und der Whisper-Prompt knapp bleibt. Gesprochene Satzzeichen gibt es nicht (entfernt).
- Schwebende **Pille**: Kapsel-Glass (`PillGlassModifier`) für Aufnahme/Status; für erweiterte **Copy- und Varianten-Karten** ein eigener `CardGlassModifier` (abgerundetes Rechteck, 14pt-Radius, tieferer Schatten) statt Kapsel — sonst „eckiger Inhalt im Pillen-Loch".

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

- Stock SwiftUI zuerst: `GroupBox`, `Form`-artige vertikale Gruppen, native `Picker`,
  `Toggle`, `TextField`, `TextEditor`, `.bordered` / `.borderedProminent` Buttons.
- `SubtleButtonStyle` nur noch für sehr kleine Inline-/Chip-Aktionen, nicht für echte Buttons.
- Neue sichtbare Action-Buttons: `PopoverActionButtonStyle(.primary/.secondary/.warning/.danger/.quiet)`.
  Echte Aktionen dürfen nicht wie nackter Text aussehen; auch kleine Aktionen bekommen Fill/Stroke
  oder werden als Icon-Button (`PopoverIconButtonStyle`) gerendert.
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
- **Eigene Identität**: Onboarding fragt einmal nach dem eigenen Namen. Derselbe Wert steht im
  Vokabular-Tab und wird lokal als feste Schreibperspektive (`Ich schreibe als ...`) sowie als
  Spracherkennungs-Hinweis verwendet. Das ist kein E-Mail-Memory, sondern Basis-Kontext für alle
  Rewrite-Modi; E-Mail-Kontext kann damit Absender/Empfänger sauberer aus `Von`/`An` ableiten.
- **Varianten-Karte in der Pille**: zwei gleich gewichtete Textkarten, je `Einfügen` und
  `Kopieren`. Keine automatische Paste, solange die Karte sichtbar ist.
- **Verfügbarkeits-Badges**: vorhandene Icons `checkmark.circle.fill` (grün) /
  `arrow.down.circle.fill` (blau) / `exclamationmark.triangle.fill` (orange) wiederverwenden.
- **Einheitliche Modellverwaltung**: Das „Lokale Modelle"-Fenster (`LocalModelsView`) verwaltet alle
  drei lokalen Modelltypen an einem Ort — Transkription (Whisper, `WhisperModelsSection`),
  Umschreiben (Ollama-LLM) und Embedding. Jede Modellzeile folgt demselben Muster: grün/blau-Badge +
  Name + Größe links, rechts Aktion(en) — `Nutzen`/`Aktiv`-Pille, `arrow.clockwise`-Icon-Button für
  „Neu laden" und `DeleteModelButton` (Papierkorb mit Bestätigung). `DeleteModelButton` ist
  Closure-basiert und für alle Modelltypen identisch. Reihen liegen auf `.liquidGlassCard(cornerRadius: 8)`,
  je Engine eine `SectionLabel`-Gruppe. Embedding-Modelle zeigen nie „Nutzen" (das setzt nur das
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

### Geltungsbereich

Liquid Glass gilt für **schwebende Surfaces**: das Popover (`MenuBarView`), die floating Recording-Pille (`RecordingPillView`), die Onboarding-Fenster-Wurzel. Dense Settings-Flächen (GroupBox-Sektionen, Formfelder, Chips innerhalb einer GroupBox) **erhalten kein Glass** — sie nutzen native SwiftUI-Controls, damit macOS 26 den Systemlook selbst rendert.

### Regel: Glass nicht stapeln

Ein Glass-Layer pro Surface-Ebene. Im Popover: `BlitztextSurface` (Fenster-Backdrop) = Layer 1. Karten wie `enginePanel` oder `accessibilityHintBanner` innerhalb des Popovers = Layer 2. Kein weiterer Glass-Layer innerhalb dieser Karten. Chips, Toggles, Picker innerhalb einer GroupBox = nullte Glass-Ebene; sie erben den Systemlook.

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

**Farbige Banner** (orange Warnings, blaue Setup-Nudge): `.liquidGlassInfoBanner(accent:)` ersetzt alle manuellen `tintFill/tintStroke`-Banner-Konstruktionen.

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
- Systemeinstellungen-Reihenfolge: Bedienungshilfen → Installation & Start → Tastenkürzel → Feedback → Einrichtung → Updates → Über & Lizenzen → Sauber Entfernen.

### In-App-Copy bleibt Deutsch

Alle Labels, Buttons, Captions, Tooltips in Deutsch (du-Form, knapp). Code, Kommentare, Commits in Englisch.

## App- und Menüleisten-Icons

- App-Icon: schwarze Rundquadrat-Fläche mit dem **rede-Mark**: weiße Sprechblase (Tail unten
  links) mit drei abgerundeten Sprechbalken — oben/unten schwarz gestanzt, Mitte Coral
  (`#FF5C4D`). Keine Zusatzsymbole, keine lauten Illustrationen, keine Verläufe im Mark.
- Quelle: `scripts/generate-icons.swift` rendert Iconset, `AppIcon.icns` und Menüleisten-PNGs
  deterministisch — Icon-Änderungen passieren im Skript, nicht in Bild-Editoren.
- macOS 26 Icon: `AppIcon.icon` ist die primäre Liquid-Glass-Quelle. Der schwarze Hintergrund
  liegt als Icon-Composer-Fill an, das rede-Mark als SVG-Layer (`rede-mark.svg`);
  `AppIcon.icns` bleibt Fallback für ältere macOS-Darstellungen.
- Menüleisten-Icon: Idle ist das monochrome Template des rede-Marks (Sprechblase, Balken
  transparent gestanzt). Während Aufnahme/Verarbeitung keine mode-spezifischen Badge-Symbole;
  nur das normale Zeichen plus kleiner pulsierender Statuspunkt.
