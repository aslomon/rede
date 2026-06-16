# rede — Memory-Subsystem: Tiefen-Spezifikation

> Aus Multi-Agent-Analyse (Facetten: Extraktion, Update-Takt, Kontext-Injektion, vergleichbare Systeme).
> Beantwortet: funktioniert das Design? · Update-Takt? · worauf achten? · Best Practices?

## Kernprinzip: Zwei Geschwindigkeiten

Die wichtigste Erkenntnis — und der Punkt, an dem das ursprüngliche Plan-Framing geschärft werden muss:
**„Kandidaten berechnen" und „Memory injizieren" sind ZWEI getrennte Vorgänge mit unterschiedlichem Takt.**

|              | Kandidaten-Berechnung                    | Injizierte Memory                                   |
| ------------ | ---------------------------------------- | --------------------------------------------------- |
| **Was**      | Begriffe zählen/gewichten aus dem Archiv | Was tatsächlich in Whisper/LLM-Prompt geht          |
| **Takt**     | häufig, billig, **im Hintergrund**       | **stabil** — ändert sich nur bei deiner Bestätigung |
| **Sichtbar** | Vorschläge in der Archiv-UI              | Wirkt sofort auf alle Modi                          |

Grund: Würde die injizierte Memory bei _jeder_ Transkription automatisch mitwandern, ändert sich dein Prompt
ständig → nicht-deterministische Ergebnisse, kein Vertrauen, keine Kuratierbarkeit. Genau deshalb trennen das
**alle** vergleichbaren Systeme (siehe unten).

---

## 1. Funktioniert das Design? — Ja, mit 4 Korrekturen

1. **Aus dem ROH-Transkript extrahieren**, nicht aus dem umgeschriebenen Endtext — das Rewrite verändert Namen/
   Begriffe und verfälscht die Fidelität.
2. **Inkrementell falten, kein 90-Tage-Rescan pro Lauf** — bei jeder neuen Transkription nur _dieses eine_
   Dokument in einen persistenten Index falten.
3. **Injektion nur auf Bestätigung** — die berechneten Kandidaten werden vorgeschlagen, aber erst nach deinem
   „Übernehmen" Teil der aktiven Memory.
4. **Frequenz × Seltenheit gaten, nicht NER-gated** — deutsche NER (`NLTagger.nameType`) überfeuert bei
   großgeschriebenen Nomen; Häufigkeit + Out-of-Dictionary-Seltenheit tragen die Last.

---

## 2. Update-Takt (die zentrale Frage) — HYBRID

**Kandidaten-Berechnung (häufig, billig, Hintergrund):**

- **Pro Lauf:** im `onRun`-Hook das neue Transkript anhängen + ein **inkrementelles** NER/Frequenz-Fold in
  `memory.json`-Zähler — auf einem `Task.detached(.utility)`, **blockiert nie** den Live-Pfad.
- **Debounced (Burst):** ~60–120 s nach dem letzten Lauf eines Bursts, **nur im Idle** (keine aktive Aufnahme):
  Recency/Decay-Neugewichtung + neue Vorschläge in der Archiv-UI. Coalesced (20 Diktate hintereinander → 1 Pass).
- **App-Start:** Catch-up, per `mtime`/Content-Hash gated (überspringt, wenn Archiv unverändert).
- **1×/Tag:** Decay + Prune (90-Tage-Fenster, alte Begriffe altern aus).
- **Manuell:** „Jetzt analysieren"-Button für sofortigen Full-Recompute.

**Injizierte Memory (stabil):**

- Ändert sich **NUR** bei deiner Bestätigung/Bearbeitung **oder** manuellem Full-Recompute — **nie** als
  Nebeneffekt der Hintergrund-Berechnung.

> **Kurzantwort:** Nicht „stündlich" oder „täglich" als starrer Cron — sondern **ereignisgesteuert + debounced +
> im Hintergrund** für die Berechnung, und **nur-auf-Bestätigung** für das, was wirklich injiziert wird.
> (Täglicher Decay-Pass ist die einzige zeitbasierte Komponente.)

---

## 3. Worauf achten (Pitfalls)

- **Whisper-224-Token-Budget:** harter Cap **~50–60 Begriffe / ≤180 Tokens**. Whisper verwirft beim Overflow die
  **frühesten** Tokens → die **besten** Begriffe ans **Ende** der Liste. Namen + Fremdwörter vor generische Fachbegriffe.
- **Kein Prompt-Churn:** Injektion nur auf Bestätigung (s. o.) — sonst Nicht-Determinismus.
- **Deutsche NER überfeuert** → Frequenz×Seltenheit, nicht NER allein.
- **Prompt-Bloat/Bias im Rewrite:** Begriffe als _Schreibweisen-Hinweis_ formulieren, nicht „benutze diese Wörter".
- **Runaway-Wachstum:** Caps + Decay + **Denylist** (von dir entfernte Begriffe kommen nie wieder).
- **PII:** Namen/E-Mails liegen on-device → opt-in, 0600, jederzeit löschbar; unter Offline-Modus klar kommuniziert.
- **Pro-Sprache scoren:** DE/EN-Tokens gegen die jeweils richtige Frequenzliste (per-Token `dominantLanguage`).

---

## 4. Best Practices (aus vergleichbaren Systemen)

- **Memory = kuratierter, gedeckelter Fact-Store, kein endloses Log.**
- **Event-driven + debounced + background** — nie den Live-Request blockieren. (Apple baut sein Custom-LM im
  Idle/Deploy; ChatGPT-Memory & mem0 extrahieren **asynchron NACH** dem Gespräch, nie mid-request.)
- **Wichtigkeit = Frequenz × Seltenheit**, gegated auf Out-of-Dictionary/Eigennamen — „nur Wörter senden, die das
  Modell verfehlt" (Deepgram-Prinzip; Google/Azure: Vokabular einmal setzen, iterativ erweitern).
- **Nutzer-Review/Forget** als erste Klasse: bestätigen, bearbeiten, entfernen, Denylist.
- **Inkrementell amortisiert**, nicht voller Rescan.

---

## Datenmodell (Skizze)

```
memory.json (separat von settings.json, 0600, opt-in)
  candidates: [ { lemma, surfaceForms[], category(name|foreign|term),
                  docFrequency, lastSeen, perCategoryVotes, score } ]
  confirmed:  [ { term, category, addedAt } ]      // → Injektion
  denylist:   [ term ]                              // entfernt, kommt nie wieder
  lastProcessed: { contentHash, date }
```

Injektion liest **nur** `confirmed` (+ existierende globale `customTerms`), dedupliziert, rankt, cappt.

## Plan-Anpassungen (vs. PLAN-v2.md Phase 4)

1. Extraktion aus **Roh-Transkript**.
2. **Zwei-Geschwindigkeiten-Takt** statt „bei jeder Transkription updaten".
3. Injektion **nur auf Bestätigung**; Whisper-Cap + Reihenfolge.
4. **Frequenz×Seltenheit-Gate** statt NER-Gate; Denylist + Decay.
